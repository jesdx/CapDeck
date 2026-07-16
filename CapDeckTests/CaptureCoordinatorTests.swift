import AppKit
@testable import CapDeck
import CoreGraphics
import Foundation
import Testing

@MainActor
struct CaptureCoordinatorTests {
    @Test
    func fullScreenCaptureCopiesResultWhenAutoCopyIsEnabled() async throws {
        let fixture = try makeFixture(autoCopy: true, permissionGranted: true)

        await fixture.coordinator.captureFullScreen()

        #expect(
            fixture.captureService.requests == [
                CaptureRequest(mode: .fullScreen, displayID: 3),
            ]
        )
        #expect(fixture.selectionService.displaySelectionCount == 1)
        #expect(fixture.clipboardService.writeCount == 1)
        #expect(fixture.previewService.presentations.count == 1)
        #expect(fixture.previewService.presentations.first?.1 == .autoHide)
        #expect(fixture.previewService.presentations.first?.2 == 2)
        #expect(fixture.saveService.processedPolicies == [.never])
        #expect(fixture.historyRecorder.records.count == 1)
        #expect(fixture.coordinator.lastSaveOutcome == .skipped)
        #expect(fixture.coordinator.state == .completed(width: 2, height: 3, copied: true))
    }

    @Test
    func newCaptureDismissesExistingPostCaptureUIBeforeSelection() async throws {
        let fixture = try makeFixture(autoCopy: true, permissionGranted: true)

        await fixture.coordinator.captureFullScreen()

        #expect(fixture.previewService.dismissCount == 1)
        #expect(fixture.historyPresenter.dismissCount == 1)
        #expect(fixture.previewService.presentations.count == 1)
    }

    @Test
    func captureIsIgnoredWhilePreviewSaveDialogIsOpen() async throws {
        let fixture = try makeFixture(autoCopy: true, permissionGranted: true)
        fixture.previewService.isPresentingModalSheet = true

        await fixture.coordinator.captureFullScreen()

        #expect(fixture.captureService.requests.isEmpty)
        #expect(fixture.previewService.dismissCount == 0)
        #expect(fixture.previewService.presentations.isEmpty)
        #expect(fixture.clipboardService.writeCount == 0)
    }

    @Test
    func captureIsIgnoredWhileHistorySaveDialogIsOpen() async throws {
        let fixture = try makeFixture(autoCopy: true, permissionGranted: true)
        fixture.historyPresenter.isPresentingModalSheet = true

        await fixture.coordinator.captureFullScreen()

        #expect(fixture.captureService.requests.isEmpty)
        #expect(fixture.historyPresenter.dismissCount == 0)
        #expect(fixture.previewService.dismissCount == 0)
    }

    @Test
    func saveFailureDoesNotDiscardClipboardOrPreview() async throws {
        let fixture = try makeFixture(
            autoCopy: true,
            permissionGranted: true,
            savePolicy: .always,
            saveOutcome: .failed("Disk is full")
        )

        await fixture.coordinator.captureFullScreen(displayID: 3)

        #expect(fixture.clipboardService.writeCount == 1)
        #expect(fixture.previewService.presentations.count == 1)
        #expect(fixture.saveService.processedPolicies == [.always])
        #expect(fixture.coordinator.lastSaveOutcome == .failed("Disk is full"))
        #expect(fixture.coordinator.state == .completed(width: 2, height: 3, copied: true))
    }

    @Test
    func askEveryTimeDiscardKeepsCompletedCapture() async throws {
        let fixture = try makeFixture(
            autoCopy: true,
            permissionGranted: true,
            savePolicy: .askEveryTime,
            saveOutcome: .discarded
        )

        await fixture.coordinator.captureFullScreen(displayID: 3)

        #expect(fixture.saveService.processedPolicies == [.askEveryTime])
        #expect(fixture.coordinator.lastSaveOutcome == .discarded)
        #expect(fixture.coordinator.state == .completed(width: 2, height: 3, copied: true))
    }

    @Test
    func deniedPermissionStopsBeforeCapture() async throws {
        let fixture = try makeFixture(autoCopy: true, permissionGranted: false)

        await fixture.coordinator.captureFullScreen()

        #expect(fixture.permissionService.requestCount == 1)
        #expect(fixture.permissionService.recoveryPromptCount == 0)
        #expect(fixture.captureService.requests.isEmpty)
        #expect(fixture.clipboardService.writeCount == 0)
        #expect(fixture.coordinator.state == .permissionDenied)
    }

    @Test
    func previouslyRequestedPermissionUsesRecoveryWithoutStackingSystemPrompt() async throws {
        let fixture = try makeFixture(autoCopy: true, permissionGranted: false)
        fixture.permissionService.requestResult = .previouslyRequested

        await fixture.coordinator.captureFullScreen()

        #expect(fixture.permissionService.requestCount == 1)
        #expect(fixture.permissionService.recoveryPromptCount == 1)
        #expect(fixture.captureService.requests.isEmpty)
        #expect(fixture.coordinator.state == .permissionDenied)
    }

    @Test
    func permissionRevokedDuringCaptureUsesTheRecoveryPath() async throws {
        let fixture = try makeFixture(autoCopy: true, permissionGranted: true)
        fixture.captureService.onCapture = {
            fixture.permissionService.isAuthorized = false
        }
        fixture.captureService.error = TestServiceError.failed

        await fixture.coordinator.captureFullScreen(displayID: 3)

        #expect(fixture.permissionService.recoveryPromptCount == 1)
        #expect(fixture.coordinator.state == .permissionDenied)
        #expect(fixture.clipboardService.writeCount == 0)
        #expect(fixture.saveService.processedPolicies.isEmpty)
        #expect(fixture.previewService.presentations.isEmpty)
        #expect(fixture.historyRecorder.records.isEmpty)
    }

    @Test
    func disappearingDisplayFailsWithoutPostCaptureSideEffects() async throws {
        let fixture = try makeFixture(autoCopy: true, permissionGranted: true)
        fixture.captureService.error = ScreenCaptureServiceError.displayUnavailable

        await fixture.coordinator.captureFullScreen(displayID: 99)

        #expect(
            fixture.coordinator.state
                == .failed(
                    message: "The selected display is no longer available."
                )
        )
        #expect(fixture.clipboardService.writeCount == 0)
        #expect(fixture.saveService.processedPolicies.isEmpty)
        #expect(fixture.previewService.presentations.isEmpty)
    }

    @Test
    func fullScreenCaptureSkipsClipboardWhenAutoCopyIsDisabled() async throws {
        let fixture = try makeFixture(autoCopy: false, permissionGranted: true)

        await fixture.coordinator.captureFullScreen()

        #expect(fixture.captureService.requests.count == 1)
        #expect(fixture.clipboardService.writeCount == 0)
        #expect(fixture.coordinator.state == .completed(width: 2, height: 3, copied: false))
    }

    @Test
    func clipboardFailureDoesNotSuppressSaveOrPreview() async throws {
        let fixture = try makeFixture(
            autoCopy: true,
            permissionGranted: true,
            previewPolicy: .always,
            savePolicy: .always,
            saveOutcome: .saved(URL(fileURLWithPath: "/tmp/Capture.png"))
        )
        fixture.clipboardService.error = ClipboardServiceError.writeFailed

        await fixture.coordinator.captureFullScreen(displayID: 3)

        #expect(fixture.clipboardService.writeCount == 1)
        #expect(fixture.saveService.processedPolicies == [.always])
        #expect(fixture.previewService.presentations.count == 1)
        #expect(fixture.previewService.presentations.first?.1 == .always)
        #expect(
            fixture.coordinator.state
                == .failed(
                    message: "The screenshot could not be copied to the clipboard."
                )
        )
    }

    @Test
    func neverPreviewPolicyDoesNotPresentPreview() async throws {
        let fixture = try makeFixture(
            autoCopy: true,
            permissionGranted: true,
            previewPolicy: .never
        )

        await fixture.coordinator.captureFullScreen(displayID: 3)

        #expect(fixture.previewService.presentations.isEmpty)
        #expect(fixture.coordinator.state == .completed(width: 2, height: 3, copied: true))
    }

    @Test
    func explicitDisplayCaptureSkipsVisualDisplaySelection() async throws {
        let fixture = try makeFixture(autoCopy: true, permissionGranted: true)

        await fixture.coordinator.captureFullScreen(displayID: 2)

        #expect(fixture.selectionService.displaySelectionCount == 0)
        #expect(
            fixture.captureService.requests == [
                CaptureRequest(mode: .fullScreen, displayID: 2),
            ]
        )
    }

    @Test
    func regionSelectionFlowsIntoCaptureAndClipboard() async throws {
        let fixture = try makeFixture(autoCopy: true, permissionGranted: true)
        let request = CaptureRequest(
            mode: .region,
            displayID: 7,
            sourceRect: CGRect(x: 10, y: 20, width: 300, height: 200)
        )
        fixture.selectionService.regionRequest = request

        await fixture.coordinator.captureRegion()

        #expect(fixture.selectionService.regionSelectionCount == 1)
        #expect(fixture.captureService.requests == [request])
        #expect(fixture.clipboardService.writeCount == 1)
    }

    @Test
    func cancelledSelectionHasNoCaptureSideEffects() async throws {
        let fixture = try makeFixture(autoCopy: true, permissionGranted: true)
        fixture.selectionService.regionRequest = nil

        await fixture.coordinator.captureRegion()

        #expect(fixture.captureService.requests.isEmpty)
        #expect(fixture.clipboardService.writeCount == 0)
        #expect(fixture.coordinator.state == .cancelled)
    }

    @Test
    func windowSelectionFlowsIntoCapture() async throws {
        let fixture = try makeFixture(autoCopy: true, permissionGranted: true)
        let request = CaptureRequest(mode: .window, windowID: 42)
        fixture.selectionService.windowRequest = request

        await fixture.coordinator.captureWindow()

        #expect(fixture.selectionService.windowSelectionCount == 1)
        #expect(fixture.captureService.requests == [request])
    }

    @Test
    func directWindowChoiceSkipsVisualSelection() async throws {
        let fixture = try makeFixture(autoCopy: true, permissionGranted: true)

        await fixture.coordinator.captureWindow(windowID: 99)

        #expect(fixture.selectionService.windowSelectionCount == 0)
        #expect(
            fixture.captureService.requests == [
                CaptureRequest(mode: .window, windowID: 99),
            ]
        )
        #expect(fixture.clipboardService.writeCount == 1)
    }

    @Test
    func refreshWindowListPublishesCapturableWindows() throws {
        let fixture = try makeFixture(autoCopy: true, permissionGranted: true)

        fixture.coordinator.refreshAvailableWindows()

        #expect(fixture.coordinator.availableWindows.count == 1)
        #expect(fixture.coordinator.availableWindows.first?.displayName == "Example — Document")
    }

    @Test
    func captureTextCopiesRecognizedTextAndSkipsImageSideEffects() async throws {
        let fixture = try makeFixture(
            autoCopy: true,
            permissionGranted: true,
            previewPolicy: .always,
            savePolicy: .always,
            recognizedText: RecognizedText(lines: [
                RecognizedTextLine(
                    text: "Hello",
                    boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10),
                    confidence: 1
                ),
            ])
        )
        fixture.selectionService.regionRequest = CaptureRequest(
            mode: .region,
            displayID: 7,
            sourceRect: CGRect(x: 0, y: 0, width: 40, height: 20)
        )

        await fixture.coordinator.captureText()

        #expect(fixture.selectionService.regionSelectionCount == 1)
        #expect(fixture.captureService.requests.count == 1)
        #expect(fixture.clipboardService.writtenText == ["Hello"])
        // No image side effects: no image on the clipboard, no save, no preview,
        // no history entry.
        #expect(fixture.clipboardService.writeCount == 0)
        #expect(fixture.saveService.processedPolicies.isEmpty)
        #expect(fixture.previewService.presentations.isEmpty)
        #expect(fixture.historyRecorder.records.isEmpty)
        #expect(fixture.coordinator.state == .textCopied)
    }

    @Test
    func captureTextReportsNoTextFoundWithoutWritingClipboard() async throws {
        let fixture = try makeFixture(
            autoCopy: true,
            permissionGranted: true,
            recognizedText: .empty
        )

        await fixture.coordinator.captureText()

        #expect(fixture.captureService.requests.count == 1)
        #expect(fixture.clipboardService.writtenText.isEmpty)
        #expect(fixture.coordinator.state == .noTextFound)
    }

    @Test
    func captureTextCancelledSelectionHasNoSideEffects() async throws {
        let fixture = try makeFixture(autoCopy: true, permissionGranted: true)
        fixture.selectionService.regionRequest = nil

        await fixture.coordinator.captureText()

        #expect(fixture.captureService.requests.isEmpty)
        #expect(fixture.clipboardService.writtenText.isEmpty)
        #expect(fixture.coordinator.state == .cancelled)
    }

    @Test
    func captureTextStopsWhenPermissionDenied() async throws {
        let fixture = try makeFixture(autoCopy: true, permissionGranted: false)

        await fixture.coordinator.captureText()

        #expect(fixture.captureService.requests.isEmpty)
        #expect(fixture.clipboardService.writtenText.isEmpty)
        #expect(fixture.coordinator.state == .permissionDenied)
    }

    private func makeFixture(
        autoCopy: Bool,
        permissionGranted: Bool,
        previewPolicy: PreviewPolicy = .autoHide,
        savePolicy: SavePolicy = .never,
        saveOutcome: CaptureSaveOutcome = .skipped,
        recognizedText: RecognizedText = .empty
    ) throws -> Fixture {
        let suiteName = "CaptureCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(autoCopy, forKey: "settings.autoCopy")
        defaults.set(previewPolicy.rawValue, forKey: "settings.previewPolicy")
        defaults.set(savePolicy.rawValue, forKey: "settings.savePolicy")

        let permissionService = PermissionServiceFake(isAuthorized: permissionGranted)
        let selectionService = SelectionServiceFake()
        let captureService = try CaptureServiceFake(result: makeCaptureResult())
        let clipboardService = ClipboardServiceFake()
        let saveService = SaveServiceFake(outcome: saveOutcome)
        let previewService = PreviewServiceFake()
        let historyRecorder = HistoryRecorderFake()
        let historyPresenter = HistoryPresenterFake()
        let textRecognizer = TextRecognizerFake(result: recognizedText)
        let textCopier = CaptureTextCopier(
            recognizer: textRecognizer,
            clipboardService: clipboardService
        )
        let settings = AppSettings(defaults: defaults)
        let coordinator = CaptureCoordinator(
            permissionService: permissionService,
            selectionPresenter: selectionService,
            captureService: captureService,
            clipboardService: clipboardService,
            saveService: saveService,
            previewPresenter: previewService,
            historyRecorder: historyRecorder,
            historyPresenter: historyPresenter,
            textCopier: textCopier,
            settings: settings
        )

        return Fixture(
            coordinator: coordinator,
            permissionService: permissionService,
            selectionService: selectionService,
            captureService: captureService,
            clipboardService: clipboardService,
            saveService: saveService,
            previewService: previewService,
            historyRecorder: historyRecorder,
            historyPresenter: historyPresenter
        )
    }

    private func makeCaptureResult() throws -> CaptureResult {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: 2,
                height: 3,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let image = try #require(context.makeImage())
        return CaptureResult(image: image, displayID: 1, timestamp: Date())
    }
}

@MainActor
private struct Fixture {
    let coordinator: CaptureCoordinator
    let permissionService: PermissionServiceFake
    let selectionService: SelectionServiceFake
    let captureService: CaptureServiceFake
    let clipboardService: ClipboardServiceFake
    let saveService: SaveServiceFake
    let previewService: PreviewServiceFake
    let historyRecorder: HistoryRecorderFake
    let historyPresenter: HistoryPresenterFake
}

@MainActor
private final class HistoryRecorderFake: CaptureHistoryRecording {
    private(set) var records: [(CaptureResult, CaptureSaveOutcome)] = []

    func record(_ result: CaptureResult, saveOutcome: CaptureSaveOutcome) {
        records.append((result, saveOutcome))
    }
}

@MainActor
private final class HistoryPresenterFake: CaptureHistoryPresenting {
    private(set) var presentCount = 0
    private(set) var dismissCount = 0
    var isPresentingModalSheet = false

    func present() {
        presentCount += 1
    }

    func dismiss() {
        dismissCount += 1
    }
}

@MainActor
private final class SelectionServiceFake: CaptureSelectionPresenting {
    var regionRequest: CaptureRequest? = CaptureRequest(
        mode: .region,
        displayID: 1,
        sourceRect: CGRect(x: 0, y: 0, width: 10, height: 10)
    )
    var windowRequest: CaptureRequest? = CaptureRequest(mode: .window, windowID: 1)
    var displayRequest: CaptureRequest? = CaptureRequest(mode: .fullScreen, displayID: 3)
    private(set) var regionSelectionCount = 0
    private(set) var windowSelectionCount = 0
    private(set) var displaySelectionCount = 0

    func availableWindows() -> [CaptureWindowOption] {
        [
            CaptureWindowOption(
                id: 42,
                applicationName: "Example",
                windowTitle: "Document"
            ),
        ]
    }

    func selectRegion() async throws -> CaptureRequest? {
        regionSelectionCount += 1
        return regionRequest
    }

    func selectWindow() async throws -> CaptureRequest? {
        windowSelectionCount += 1
        return windowRequest
    }

    func selectDisplay() async throws -> CaptureRequest? {
        displaySelectionCount += 1
        return displayRequest
    }
}

@MainActor
private final class PermissionServiceFake: ScreenCapturePermissionProviding {
    var isAuthorized: Bool
    var requestResult: ScreenCapturePermissionRequestResult
    private(set) var requestCount = 0
    private(set) var recoveryPromptCount = 0

    init(isAuthorized: Bool) {
        self.isAuthorized = isAuthorized
        requestResult = isAuthorized ? .authorized : .systemPromptPresented
    }

    func requestAccess() -> ScreenCapturePermissionRequestResult {
        requestCount += 1
        return requestResult
    }

    func presentRecoveryPrompt() {
        recoveryPromptCount += 1
    }

    func openSystemSettings() {}
}

@MainActor
private final class CaptureServiceFake: ScreenCapturing {
    private(set) var requests: [CaptureRequest] = []
    let result: CaptureResult
    var error: Error?
    var onCapture: (() -> Void)?

    init(result: CaptureResult) {
        self.result = result
    }

    func capture(_ request: CaptureRequest) async throws -> CaptureResult {
        requests.append(request)
        onCapture?()
        if let error {
            throw error
        }
        return result
    }
}

private struct TextRecognizerFake: TextRecognizing {
    var result: RecognizedText = .empty
    var error: Error?

    func recognizeText(in _: CaptureResult) async throws -> RecognizedText {
        if let error {
            throw error
        }
        return result
    }
}

@MainActor
private final class ClipboardServiceFake: ClipboardWriting {
    private(set) var writeCount = 0
    private(set) var writtenText: [String] = []
    var error: Error?

    func write(_: CaptureResult) throws {
        writeCount += 1
        if let error {
            throw error
        }
    }

    func writeText(_ text: String) throws {
        writtenText.append(text)
        if let error {
            throw error
        }
    }
}

@MainActor
private final class SaveServiceFake: CaptureSaving {
    let outcome: CaptureSaveOutcome
    private(set) var processedPolicies: [SavePolicy] = []

    init(outcome: CaptureSaveOutcome) {
        self.outcome = outcome
    }

    func process(
        _: CaptureResult,
        policy: SavePolicy,
        configuration _: CaptureSaveConfiguration
    ) async -> CaptureSaveOutcome {
        processedPolicies.append(policy)
        return outcome
    }

    func saveAs(
        _: CaptureResult,
        configuration _: CaptureSaveConfiguration,
        presentingWindow _: NSWindow?
    ) async -> CaptureSaveOutcome {
        outcome
    }
}

@MainActor
private final class PreviewServiceFake: CapturePreviewPresenting {
    private(set) var presentations: [(CaptureResult, PreviewPolicy, TimeInterval)] = []
    private(set) var fullPresentations: [CaptureResult] = []
    private(set) var dismissCount = 0
    var isPresentingModalSheet = false

    func present(
        _ result: CaptureResult,
        policy: PreviewPolicy,
        duration: TimeInterval
    ) {
        presentations.append((result, policy, duration))
    }

    func dismiss() {
        dismissCount += 1
    }

    func presentFull(_ result: CaptureResult) {
        fullPresentations.append(result)
    }
}
