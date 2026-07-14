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
    case cancelled
    case completed(width: Int, height: Int, copied: Bool)
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
        case .cancelled:
            "Capture cancelled"
        case let .completed(width, height, copied):
            copied
                ? "Copied \(width) × \(height) to clipboard"
                : "Captured \(width) × \(height)"
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
        case .requestingPermission, .delaying, .selecting, .capturing:
            "ellipsis.circle"
        case .cancelled:
            "xmark.circle"
        case .completed:
            "checkmark.circle.fill"
        case .permissionDenied:
            "lock.trianglebadge.exclamationmark"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var isBusy: Bool {
        switch self {
        case .requestingPermission, .delaying, .selecting, .capturing:
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

    private func capture(
        mode: CaptureMode,
        displayID: CGDirectDisplayID? = nil,
        requestOverride: CaptureRequest? = nil
    ) async {
        guard !state.isBusy else { return }
        // A capture dismisses any open post-capture UI. If the user has a modal
        // save dialog attached to the preview, annotation editor, or history
        // window, tearing it down here would silently cancel their in-progress
        // save, so ignore the request instead (as with an in-flight capture).
        guard !previewPresenter.isPresentingModalSheet,
            !historyPresenter.isPresentingModalSheet
        else {
            Self.logger.notice("Capture request ignored while a save dialog is open")
            return
        }
        let startedAt = ContinuousClock.now
        Self.logger.info("Capture started mode=\(String(describing: mode), privacy: .public)")
        previewPresenter.dismiss()
        historyPresenter.dismiss()

        let permissionResult = await ensurePermission()
        guard permissionResult == .authorized else {
            state = .permissionDenied
            if permissionResult == .previouslyRequested {
                permissionService.presentRecoveryPrompt()
            }
            return
        }

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
                "Capture completed mode=\(String(describing: mode), privacy: .public) size=\(result.pixelWidth, privacy: .public)x\(result.pixelHeight, privacy: .public) elapsed=\(String(describing: elapsed), privacy: .public)"
            )

            if let clipboardError {
                state = .failed(message: clipboardError.localizedDescription)
            }
        } catch {
            // Permission can be revoked after the preflight check but before
            // ScreenCaptureKit finishes producing the image. Re-check here so
            // the user receives the same recovery path as an initial denial.
            if !permissionService.isAuthorized {
                state = .permissionDenied
                permissionService.presentRecoveryPrompt()
            } else {
                state = .failed(message: error.localizedDescription)
            }
            Self.logger.error(
                "Capture failed mode=\(String(describing: mode), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func openPermissionSettings() {
        permissionService.openSystemSettings()
    }

    func resetStatus() {
        state = .idle
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
