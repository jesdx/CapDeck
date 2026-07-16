import Combine
import CoreGraphics
import Foundation
import OSLog

enum CaptureWorkflowState: Equatable {
    case idle
    case requestingPermission
    case delaying(seconds: Int)
    case selecting(CaptureMode)
    case capturing
    case recognizingText
    case cancelled
    case completed(width: Int, height: Int, copied: Bool)
    case textCopied
    case noTextFound
    case permissionDenied
    case failed(message: String)

    var statusText: String {
        switch self {
        case .idle:
            "CapDeck is ready"
        case .requestingPermission:
            "Waiting for Screen Recording permission…"
        case let .delaying(seconds):
            "Capturing in \(seconds) seconds…"
        case .selecting(.region):
            "Drag to select a region"
        case .selecting(.window):
            "Choose a window"
        case .selecting(.fullScreen):
            "Preparing capture…"
        case .capturing:
            "Capturing screen…"
        case .recognizingText:
            "Recognizing text…"
        case .cancelled:
            "Capture cancelled"
        case let .completed(width, height, copied):
            copied
                ? "Copied \(width) × \(height) to clipboard"
                : "Captured \(width) × \(height)"
        case .textCopied:
            "Text copied to clipboard"
        case .noTextFound:
            "No text found in selection"
        case .permissionDenied:
            "Screen Recording permission is required"
        case let .failed(message):
            message
        }
    }

    var statusSymbol: String {
        switch self {
        case .idle:
            "circle.fill"
        case .requestingPermission, .delaying, .selecting, .capturing, .recognizingText:
            "ellipsis.circle"
        case .cancelled:
            "xmark.circle"
        case .completed, .textCopied:
            "checkmark.circle.fill"
        case .noTextFound:
            "text.magnifyingglass"
        case .permissionDenied:
            "lock.trianglebadge.exclamationmark"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var isBusy: Bool {
        switch self {
        case .requestingPermission, .delaying, .selecting, .capturing, .recognizingText:
            true
        default:
            false
        }
    }
}

@MainActor
final class CaptureCoordinator: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.jesdx.capdeck",
        category: "CaptureWorkflow"
    )
    @Published private(set) var state: CaptureWorkflowState = .idle
    @Published private(set) var availableWindows: [CaptureWindowOption] = []
    @Published private(set) var lastSaveOutcome: CaptureSaveOutcome = .skipped

    private let permissionService: ScreenCapturePermissionProviding
    private let selectionPresenter: CaptureSelectionPresenting
    private let captureService: ScreenCapturing
    private let clipboardService: ClipboardWriting
    private let saveService: CaptureSaving
    private let previewPresenter: CapturePreviewPresenting
    private let historyRecorder: CaptureHistoryRecording
    private let historyPresenter: CaptureHistoryPresenting
    private let textCopier: CaptureTextCopier
    private let settings: AppSettings

    init(
        permissionService: ScreenCapturePermissionProviding,
        selectionPresenter: CaptureSelectionPresenting,
        captureService: ScreenCapturing,
        clipboardService: ClipboardWriting,
        saveService: CaptureSaving,
        previewPresenter: CapturePreviewPresenting,
        historyRecorder: CaptureHistoryRecording,
        historyPresenter: CaptureHistoryPresenting,
        textCopier: CaptureTextCopier,
        settings: AppSettings
    ) {
        self.permissionService = permissionService
        self.selectionPresenter = selectionPresenter
        self.captureService = captureService
        self.clipboardService = clipboardService
        self.saveService = saveService
        self.previewPresenter = previewPresenter
        self.historyRecorder = historyRecorder
        self.historyPresenter = historyPresenter
        self.textCopier = textCopier
        self.settings = settings
    }

    func captureRegion() async {
        await capture(mode: .region)
    }

    func captureWindow() async {
        await capture(mode: .window)
    }

    func captureWindow(windowID: CGWindowID) async {
        await capture(
            mode: .window,
            requestOverride: CaptureRequest(mode: .window, windowID: windowID)
        )
    }

    func refreshAvailableWindows() {
        availableWindows = Array(selectionPresenter.availableWindows().prefix(15))
    }

    func captureFullScreen(displayID: CGDirectDisplayID? = nil) async {
        await capture(mode: .fullScreen, displayID: displayID)
    }

    /// Region select → capture → OCR → clipboard, with none of the image-capture
    /// side effects: no image on the clipboard, no save, no preview, and no
    /// history entry. The user wanted the text, not the screenshot.
    func captureText() async {
        guard canStartCapture() else { return }
        Self.logger.info("Capture Text started")
        previewPresenter.dismiss()
        historyPresenter.dismiss()

        guard await ensureAuthorizedOrDeny() else { return }

        do {
            state = .selecting(.region)
            guard let request = try await selectionPresenter.selectRegion() else {
                state = .cancelled
                return
            }

            // Give WindowServer one frame to remove the selection overlays.
            try await Task.sleep(for: .milliseconds(100))

            state = .capturing
            let result = try await captureService.capture(request)

            state = .recognizingText
            switch await textCopier.copyText(from: result) {
            case .copied:
                state = .textCopied
            case .noTextFound:
                state = .noTextFound
            case .cancelled:
                state = .cancelled
            case .failed:
                state = .failed(
                    message: TextRecognitionServiceError.recognitionFailed.localizedDescription
                )
            }
        } catch {
            handleCaptureFailure(error, label: "Capture Text")
        }
    }

    private func capture(
        mode: CaptureMode,
        displayID: CGDirectDisplayID? = nil,
        requestOverride: CaptureRequest? = nil
    ) async {
        guard canStartCapture() else { return }
        let startedAt = ContinuousClock.now
        Self.logger.info("Capture started mode=\(String(describing: mode), privacy: .public)")
        previewPresenter.dismiss()
        historyPresenter.dismiss()

        guard await ensureAuthorizedOrDeny() else { return }

        do {
            var usedVisualSelection = false
            if settings.captureDelay > 0 {
                state = .delaying(seconds: Int(settings.captureDelay.rounded()))
                try await Task.sleep(for: .seconds(settings.captureDelay))
            }

            let request: CaptureRequest
            switch mode {
            case .region:
                state = .selecting(.region)
                usedVisualSelection = true
                guard let selection = try await selectionPresenter.selectRegion() else {
                    state = .cancelled
                    return
                }
                request = selection
            case .window:
                if let requestOverride {
                    request = requestOverride
                } else {
                    state = .selecting(.window)
                    usedVisualSelection = true
                    guard let selection = try await selectionPresenter.selectWindow() else {
                        state = .cancelled
                        return
                    }
                    request = selection
                }
            case .fullScreen:
                if let displayID {
                    request = CaptureRequest(mode: .fullScreen, displayID: displayID)
                } else {
                    state = .selecting(.fullScreen)
                    usedVisualSelection = true
                    guard let selection = try await selectionPresenter.selectDisplay() else {
                        state = .cancelled
                        return
                    }
                    request = selection
                }
            }

            // Give WindowServer one frame to remove the selection overlays.
            if usedVisualSelection {
                try await Task.sleep(for: .milliseconds(100))
            }

            state = .capturing
            let result = try await captureService.capture(request)
            let shouldCopy = settings.isAutoCopyEnabled
            var copied = false
            var clipboardError: Error?

            if shouldCopy {
                do {
                    try clipboardService.write(result)
                    copied = true
                } catch {
                    clipboardError = error
                }
            }

            lastSaveOutcome = await saveService.process(
                result,
                policy: settings.savePolicy,
                configuration: settings.saveConfiguration
            )

            state = .completed(
                width: result.pixelWidth,
                height: result.pixelHeight,
                copied: copied
            )

            if settings.previewPolicy != .never {
                previewPresenter.present(
                    result,
                    policy: settings.previewPolicy,
                    duration: settings.previewDuration
                )
            }

            historyRecorder.record(result, saveOutcome: lastSaveOutcome)

            let elapsed = startedAt.duration(to: .now)
            Self.logger.notice(
                """
                Capture completed mode=\(String(describing: mode), privacy: .public) \
                size=\(result.pixelWidth, privacy: .public)x\(result.pixelHeight, privacy: .public) \
                elapsed=\(String(describing: elapsed), privacy: .public)
                """
            )

            if let clipboardError {
                state = .failed(message: clipboardError.localizedDescription)
            }
        } catch {
            handleCaptureFailure(error, label: "Capture mode=\(String(describing: mode))")
        }
    }

    func openPermissionSettings() {
        permissionService.openSystemSettings()
    }

    func resetStatus() {
        state = .idle
    }

    /// Rejects re-entry while a capture is in flight and refuses to proceed
    /// while a modal save sheet is attached to the preview, annotation editor,
    /// or history window — tearing that down would silently cancel the user's
    /// in-progress save. Returns false when the request should be ignored.
    private func canStartCapture() -> Bool {
        guard !state.isBusy else { return false }
        guard !previewPresenter.isPresentingModalSheet,
              !historyPresenter.isPresentingModalSheet
        else {
            Self.logger.notice("Capture request ignored while a save dialog is open")
            return false
        }
        return true
    }

    /// Runs the permission preflight, moving to `.permissionDenied` and showing
    /// the recovery prompt when access is unavailable. Returns true when capture
    /// may proceed.
    private func ensureAuthorizedOrDeny() async -> Bool {
        let result = await ensurePermission()
        guard result == .authorized else {
            state = .permissionDenied
            if result == .previouslyRequested {
                permissionService.presentRecoveryPrompt()
            }
            return false
        }
        return true
    }

    /// Maps a thrown capture error to its terminal state. Permission can be
    /// revoked after the preflight check but before ScreenCaptureKit finishes
    /// producing the image, so a revocation gets the same recovery path as an
    /// initial denial; everything else is a failure.
    private func handleCaptureFailure(_ error: Error, label: String) {
        if !permissionService.isAuthorized {
            state = .permissionDenied
            permissionService.presentRecoveryPrompt()
        } else {
            state = .failed(message: error.localizedDescription)
        }
        Self.logger.error(
            "\(label, privacy: .public) failed error=\(error.localizedDescription, privacy: .private)"
        )
    }

    private func ensurePermission() async -> ScreenCapturePermissionRequestResult {
        if permissionService.isAuthorized {
            return .authorized
        }

        state = .requestingPermission
        let result = permissionService.requestAccess()

        if result == .authorized {
            return .authorized
        }

        // macOS may update the preflight result immediately after the prompt.
        await Task.yield()
        return permissionService.isAuthorized ? .authorized : result
    }
}
