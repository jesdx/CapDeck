import AppKit
import Combine

@MainActor
final class DependencyContainer: ObservableObject {
    let settings: AppSettings
    let displayService: DisplayProviding
    let captureCoordinator: CaptureCoordinator
    let globalShortcuts: GlobalShortcutService
    let launchAtLogin: LaunchAtLoginService
    let softwareUpdate: SoftwareUpdateService
    let historyStore: CaptureHistoryStore
    let historyPresenter: CaptureHistoryPresenting

    init(
        settings: AppSettings? = nil,
        displayService: DisplayProviding? = nil,
        permissionService: ScreenCapturePermissionProviding? = nil,
        selectionPresenter: CaptureSelectionPresenting? = nil,
        captureService: ScreenCapturing? = nil,
        clipboardService: ClipboardWriting? = nil,
        textRecognizer: TextRecognizing? = nil,
        softwareUpdate: SoftwareUpdateService? = nil
    ) {
        let resolvedSettings = settings ?? AppSettings()
        let resolvedDisplayService = displayService ?? DisplayService()
        let resolvedPermissionService = permissionService ?? ScreenCapturePermissionService()
        let resolvedSelectionPresenter =
            selectionPresenter
                ?? CaptureSelectionPresenter(displayService: resolvedDisplayService)
        let resolvedCaptureService = captureService ?? ScreenCaptureService()
        let resolvedClipboardService = clipboardService ?? PasteboardClipboardService()
        let resolvedTextRecognizer = textRecognizer ?? VisionTextRecognitionService()
        let resolvedTextCopier = CaptureTextCopier(
            recognizer: resolvedTextRecognizer,
            clipboardService: resolvedClipboardService
        )
        let resolvedSaveService = CaptureFileService()
        let resolvedAnnotationPresenter = AnnotationEditorPresenter(
            clipboardService: resolvedClipboardService,
            saveService: resolvedSaveService,
            textCopier: resolvedTextCopier,
            configurationProvider: { resolvedSettings.saveConfiguration }
        )
        let resolvedPreviewPresenter = CapturePreviewPresenter(
            annotationPresenter: resolvedAnnotationPresenter,
            clipboardService: resolvedClipboardService,
            displayService: resolvedDisplayService,
            saveService: resolvedSaveService,
            textCopier: resolvedTextCopier,
            configurationProvider: { resolvedSettings.saveConfiguration }
        )
        let resolvedHistoryStore = CaptureHistoryStore()
        let resolvedHistoryPresenter = CaptureHistoryPresenter(
            store: resolvedHistoryStore,
            clipboardService: resolvedClipboardService,
            previewPresenter: resolvedPreviewPresenter,
            saveService: resolvedSaveService,
            textCopier: resolvedTextCopier,
            configurationProvider: { resolvedSettings.saveConfiguration }
        )

        self.settings = resolvedSettings
        self.displayService = resolvedDisplayService
        historyStore = resolvedHistoryStore
        historyPresenter = resolvedHistoryPresenter
        launchAtLogin = LaunchAtLoginService()
        self.softwareUpdate = softwareUpdate ?? SoftwareUpdateService(
            startingUpdater: Self.shouldStartUpdater
        )
        let coordinator = CaptureCoordinator(
            permissionService: resolvedPermissionService,
            selectionPresenter: resolvedSelectionPresenter,
            captureService: resolvedCaptureService,
            clipboardService: resolvedClipboardService,
            saveService: resolvedSaveService,
            previewPresenter: resolvedPreviewPresenter,
            historyRecorder: resolvedHistoryStore,
            historyPresenter: resolvedHistoryPresenter,
            settings: resolvedSettings
        )
        captureCoordinator = coordinator
        globalShortcuts = GlobalShortcutService { action in
            guard !coordinator.state.isBusy else { return }
            Task {
                switch action {
                case .captureRegion:
                    await coordinator.captureRegion()
                case .captureWindow:
                    await coordinator.captureWindow()
                case .captureFullScreen:
                    await coordinator.captureFullScreen(
                        displayID: resolvedDisplayService.displayUnderPointer()?.id
                    )
                }
            }
        }
        globalShortcuts.startWhenApplicationIsReady()
    }

    private static var shouldStartUpdater: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["CAPDECK_UI_TESTING"] != "1"
            && environment["XCTestConfigurationFilePath"] == nil
    }
}
