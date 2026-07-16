import AppKit
@testable import CapDeck
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing

struct CapturePreviewCompletionPolicyTests {
    @Test
    func closesOnlyAfterSuccessfulCopy() {
        #expect(CapturePreviewCompletionPolicy.shouldCloseAfterCopy(succeeded: true))
        #expect(!CapturePreviewCompletionPolicy.shouldCloseAfterCopy(succeeded: false))
    }

    @Test
    func closesOnlyAfterSuccessfulSave() {
        let savedURL = URL(fileURLWithPath: "/tmp/CapDeck-test.png")

        #expect(CapturePreviewCompletionPolicy.shouldCloseAfterSave(.saved(savedURL)))
        #expect(!CapturePreviewCompletionPolicy.shouldCloseAfterSave(.discarded))
        #expect(!CapturePreviewCompletionPolicy.shouldCloseAfterSave(.failed("Disk full")))
        #expect(!CapturePreviewCompletionPolicy.shouldCloseAfterSave(.skipped))
    }
}

@MainActor
struct GlobalShortcutServiceTests {
    @Test
    func registersEveryDefaultShortcutAndRoutesActions() throws {
        let registrar = GlobalShortcutRegistrarFake()
        var receivedActions: [GlobalShortcutAction] = []
        let service = try GlobalShortcutService(
            registrar: registrar,
            defaults: makeShortcutDefaults()
        ) { action in
            receivedActions.append(action)
        }

        service.start()
        registrar.trigger(.captureWindow)

        #expect(registrar.registeredActions == GlobalShortcutAction.allCases)
        #expect(service.status(for: .captureRegion) == .registered)
        #expect(service.shortcut(for: .captureRegion).displayValue == "⌃⇧J")
        #expect(receivedActions == [.captureWindow])
    }

    @Test
    func publishesRegistrationConflicts() throws {
        let registrar = GlobalShortcutRegistrarFake(conflict: .captureFullScreen)
        let service = try GlobalShortcutService(
            registrar: registrar,
            defaults: makeShortcutDefaults()
        ) { _ in }

        service.start()

        #expect(service.status(for: .captureRegion) == .registered)
        #expect(service.status(for: .captureFullScreen) == .conflict)
    }

    @Test
    func customShortcutPersistsAcrossServiceInstances() throws {
        let defaults = try makeShortcutDefaults()
        let registrar = GlobalShortcutRegistrarFake()
        let service = GlobalShortcutService(registrar: registrar, defaults: defaults) { _ in }
        let custom = GlobalShortcut(
            keyCode: 46,
            modifiers: UInt32(controlKey | optionKey),
            keyLabel: "M"
        )

        service.start()
        #expect(service.setShortcut(custom, for: .captureRegion))

        let restored = GlobalShortcutService(
            registrar: GlobalShortcutRegistrarFake(),
            defaults: defaults
        ) { _ in }
        #expect(restored.shortcut(for: .captureRegion) == custom)
    }

    @Test
    func conflictKeepsThePreviousWorkingShortcut() throws {
        let defaults = try makeShortcutDefaults()
        let rejected = GlobalShortcut(
            keyCode: 46,
            modifiers: UInt32(controlKey | optionKey),
            keyLabel: "M"
        )
        let registrar = GlobalShortcutRegistrarFake(conflictingShortcut: rejected)
        let service = GlobalShortcutService(registrar: registrar, defaults: defaults) { _ in }
        let original = service.shortcut(for: .captureRegion)

        service.start()
        #expect(!service.setShortcut(rejected, for: .captureRegion))

        #expect(service.shortcut(for: .captureRegion) == original)
        #expect(service.status(for: .captureRegion) == .registered)
        #expect(service.errors[.captureRegion] != nil)
    }

    private func makeShortcutDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "GlobalShortcutServiceTests.\(UUID().uuidString)"))
    }
}

@MainActor
struct AppSettingsTests {
    @Test
    func usesClipboardFirstSafeDefaults() throws {
        let settings = try AppSettings(defaults: makeDefaults())

        #expect(settings.isAutoCopyEnabled)
        #expect(settings.savePolicy == .never)
        #expect(settings.previewPolicy == .autoHide)
        #expect(settings.previewDuration == 2)
        #expect(settings.captureDelay == 0)
        #expect(settings.imageFormat == .png)
        #expect(settings.filenamePattern == FilenamePattern.defaultValue)
        #expect(settings.isMenuBarIconVisible)
        #expect(settings.isAIWorkflowPresetActive)
    }

    @Test
    func persistsSettingsAcrossInstances() throws {
        let defaults = try makeDefaults()
        let first = AppSettings(defaults: defaults)
        first.isAutoCopyEnabled = false
        first.savePolicy = .askEveryTime
        first.previewPolicy = .always
        first.previewDuration = 10
        first.captureDelay = 5
        first.imageFormat = .jpeg
        first.jpegQuality = 0.7
        first.filenamePattern = "Shot-{timestamp}"
        first.isMenuBarIconVisible = false

        let restored = AppSettings(defaults: defaults)

        #expect(!restored.isAutoCopyEnabled)
        #expect(restored.savePolicy == .askEveryTime)
        #expect(restored.previewPolicy == .always)
        #expect(restored.previewDuration == 10)
        #expect(restored.captureDelay == 5)
        #expect(restored.imageFormat == .jpeg)
        #expect(restored.jpegQuality == 0.7)
        #expect(restored.filenamePattern == "Shot-{timestamp}")
        #expect(!restored.isMenuBarIconVisible)
    }

    @Test
    func migratesLegacySaveAndPreviewBooleans() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "settings.autoSave")
        defaults.set(false, forKey: "settings.previewEnabled")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.savePolicy == .always)
        #expect(settings.previewPolicy == .never)
        #expect(defaults.integer(forKey: "settings.schemaVersion") == 1)
        #expect(defaults.object(forKey: "settings.autoSave") == nil)
        #expect(defaults.object(forKey: "settings.previewEnabled") == nil)
    }

    @Test
    func appliesAIWorkflowPresetWithoutChangingCaptureDelay() throws {
        let settings = try AppSettings(defaults: makeDefaults())
        settings.isAutoCopyEnabled = false
        settings.savePolicy = .always
        settings.previewPolicy = .never
        settings.previewDuration = 10
        settings.captureDelay = 3

        settings.applyAIWorkflowPreset()

        #expect(settings.isAIWorkflowPresetActive)
        #expect(settings.captureDelay == 3)
    }

    @Test
    func restoreDefaultsResetsCaptureAndPostCapturePreferences() throws {
        let settings = try AppSettings(defaults: makeDefaults())
        settings.isAutoCopyEnabled = false
        settings.savePolicy = .always
        settings.previewPolicy = .never
        settings.captureDelay = 5
        settings.imageFormat = .jpeg
        settings.jpegQuality = 0.4
        settings.filenamePattern = "Custom"
        settings.isMenuBarIconVisible = false

        settings.restoreDefaults()

        #expect(settings.isAIWorkflowPresetActive)
        #expect(settings.captureDelay == 0)
        #expect(settings.imageFormat == .png)
        #expect(settings.jpegQuality == 0.9)
        #expect(settings.filenamePattern == FilenamePattern.defaultValue)
        #expect(settings.isMenuBarIconVisible)
        #expect(settings.saveFolderBookmark == nil)
    }

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "AppSettingsTests.\(UUID().uuidString)"))
    }
}

@MainActor
struct SoftwareUpdateServiceTests {
    @Test
    func manualCheckRunsOnlyWhenTheUpdaterIsReady() {
        var checkCount = 0
        let ready = SoftwareUpdateService(
            displayVersion: "1.2.0 (Build 3)",
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: false,
            checkAction: { checkCount += 1 }
        )
        let unavailable = SoftwareUpdateService(
            displayVersion: "1.2.0 (Build 3)",
            canCheckForUpdates: false,
            automaticallyChecksForUpdates: false,
            checkAction: { checkCount += 1 }
        )

        ready.checkForUpdates()
        unavailable.checkForUpdates()

        #expect(checkCount == 1)
        #expect(ready.displayVersion == "1.2.0 (Build 3)")
    }

    @Test
    func automaticCheckPreferenceChangesOnlyOnUserTransitions() {
        var changes: [Bool] = []
        let service = SoftwareUpdateService(
            displayVersion: "1.2.0 (Build 3)",
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: false,
            automaticChecksAction: { changes.append($0) }
        )

        service.setAutomaticallyChecksForUpdates(true)
        service.setAutomaticallyChecksForUpdates(true)
        service.setAutomaticallyChecksForUpdates(false)

        #expect(changes == [true, false])
        #expect(!service.automaticallyChecksForUpdates)
    }
}

@MainActor
struct ScreenCapturePermissionServiceTests {
    @Test
    func presentsTheSystemRequestOnlyOnceAcrossServiceInstances() throws {
        let defaults = try #require(
            UserDefaults(suiteName: "ScreenCapturePermissionServiceTests.\(UUID().uuidString)")
        )
        var requestCount = 0
        let request: () -> Bool = {
            requestCount += 1
            return false
        }
        let first = ScreenCapturePermissionService(
            defaults: defaults,
            preflightAccess: { false },
            requestSystemAccess: request
        )

        #expect(first.requestAccess() == .systemPromptPresented)

        let relaunched = ScreenCapturePermissionService(
            defaults: defaults,
            preflightAccess: { false },
            requestSystemAccess: request
        )
        #expect(relaunched.requestAccess() == .previouslyRequested)
        #expect(requestCount == 1)
    }

    @Test
    func authorizedAccessNeverPresentsTheSystemRequest() throws {
        let defaults = try #require(
            UserDefaults(suiteName: "ScreenCapturePermissionServiceTests.\(UUID().uuidString)")
        )
        var requestCount = 0
        let service = ScreenCapturePermissionService(
            defaults: defaults,
            preflightAccess: { true },
            requestSystemAccess: {
                requestCount += 1
                return false
            }
        )

        #expect(service.requestAccess() == .authorized)
        #expect(requestCount == 0)
    }
}

@MainActor
struct LaunchAtLoginServiceTests {
    @Test
    func registersAndUnregistersTheMainApp() {
        let controller = LaunchAtLoginControllerFake()
        let service = LaunchAtLoginService(controller: controller)

        service.setEnabled(true)
        #expect(service.status == .enabled)
        #expect(service.isRequested)
        #expect(controller.registerCount == 1)

        service.setEnabled(false)
        #expect(service.status == .disabled)
        #expect(!service.isRequested)
        #expect(controller.unregisterCount == 1)
    }

    @Test
    func exposesApprovalRequiredAsARequestedLoginItem() {
        let controller = LaunchAtLoginControllerFake(status: .requiresApproval)
        let service = LaunchAtLoginService(controller: controller)

        #expect(service.status == .requiresApproval)
        #expect(service.isRequested)

        service.openSystemSettings()
        #expect(controller.openSettingsCount == 1)
    }

    @Test
    func reportsRegistrationErrorsWithoutClaimingSuccess() {
        let controller = LaunchAtLoginControllerFake(registerError: TestServiceError.failed)
        let service = LaunchAtLoginService(controller: controller)

        service.setEnabled(true)

        #expect(service.status == .disabled)
        #expect(!service.isRequested)
        #expect(service.errorMessage != nil)
    }
}

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

    private func makeFixture(
        autoCopy: Bool,
        permissionGranted: Bool,
        previewPolicy: PreviewPolicy = .autoHide,
        savePolicy: SavePolicy = .never,
        saveOutcome: CaptureSaveOutcome = .skipped
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
struct CaptureHistoryStoreTests {
    @Test
    func retainsNewestEntriesWithinTheCountLimit() throws {
        let store = CaptureHistoryStore(maximumCount: 3, maximumPixelBytes: .max)

        for second in 0 ..< 5 {
            try store.record(
                makeResult(width: 2, height: 2, timestamp: Date(timeIntervalSince1970: Double(second))),
                saveOutcome: .skipped
            )
        }

        #expect(store.entries.count == 3)
        #expect(store.entries.map(\.result.timestamp.timeIntervalSince1970) == [4, 3, 2])
        #expect(store.entries.allSatisfy { $0.savedURL == nil })
    }

    @Test
    func memoryBudgetEvictsOlderImagesButKeepsNewestCapture() throws {
        let sample = try makeResult(width: 20, height: 20)
        let entryBytes = sample.image.bytesPerRow * sample.image.height
        let store = CaptureHistoryStore(
            maximumCount: 10,
            maximumPixelBytes: entryBytes * 2
        )

        store.record(sample, saveOutcome: .skipped)
        try store.record(makeResult(width: 20, height: 20), saveOutcome: .skipped)
        try store.record(makeResult(width: 20, height: 20), saveOutcome: .skipped)

        #expect(store.entries.count == 2)
        #expect(store.estimatedPixelBytes <= entryBytes * 2)
    }

    @Test
    func savedReferenceIsMetadataOnlyAndClearReleasesSessionHistory() throws {
        let store = CaptureHistoryStore()
        let url = URL(fileURLWithPath: "/tmp/user-selected/CapDeck.png")
        try store.record(makeResult(width: 4, height: 3), saveOutcome: .saved(url))

        #expect(store.entries.first?.savedURL == url)
        store.clear()
        #expect(store.entries.isEmpty)
        #expect(store.estimatedPixelBytes == 0)
    }

    private func makeResult(
        width: Int,
        height: Int,
        timestamp: Date = Date()
    ) throws -> CaptureResult {
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        return try CaptureResult(
            image: #require(context.makeImage()),
            displayID: 1,
            timestamp: timestamp
        )
    }
}

@MainActor
struct CaptureSavingTests {
    @Test
    func savePanelAttachesAboveItsPresentingWindow() async throws {
        let parent = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        parent.title = "Save Panel Test Parent"
        parent.makeKeyAndOrderFront(nil)
        defer {
            parent.orderOut(nil)
            parent.close()
        }

        let context = try #require(
            CGContext(
                data: nil,
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let result = try CaptureResult(
            image: #require(context.makeImage()),
            displayID: 1,
            timestamp: Date()
        )
        let service = CaptureFileService()
        let saveTask = Task {
            await service.saveAs(
                result,
                configuration: CaptureSaveConfiguration(
                    format: .png,
                    jpegQuality: 0.9,
                    filenamePattern: "CapDeck-Sheet-Test",
                    folderBookmark: nil
                ),
                presentingWindow: parent
            )
        }

        for _ in 0 ..< 100 where parent.attachedSheet == nil {
            try await Task.sleep(for: .milliseconds(20))
        }

        let savePanel = try #require(parent.attachedSheet as? NSSavePanel)
        #expect(savePanel.sheetParent === parent)
        savePanel.cancel(nil)
        #expect(await saveTask.value == .discarded)
    }

    @Test
    func filenamePatternRendersStableTokens() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = 2026
        components.month = 7
        components.day = 14
        components.hour = 9
        components.minute = 8
        components.second = 7
        let date = try #require(components.date)

        let filename = try FilenamePattern.render(
            "Capture-{date}-{time}-{timestamp}",
            date: date
        )

        #expect(filename == "Capture-2026-07-14-09-08-07-20260714-090807")
    }

    @Test
    func filenamePatternRejectsUnsafeCharactersAndUnknownTokens() {
        #expect(FilenamePattern.validate("folder/name") == .invalidCharacter("/"))
        #expect(FilenamePattern.validate("Capture-{screen}") == .unsupportedToken("screen"))
    }

    @Test
    func filenamePatternRejectsLeadingDotHiddenFiles() {
        #expect(FilenamePattern.validate(".hidden") == .leadingDot)
        #expect(FilenamePattern.validate("  .{date}") == .leadingDot)
        #expect(FilenamePattern.validate("CapDeck-{date}") == nil)
    }

    @Test
    func encodesPNGAndJPEGAtOriginalPixelDimensions() throws {
        let context = try #require(
            CGContext(
                data: nil,
                width: 7,
                height: 5,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let image = try #require(context.makeImage())

        for format in ImageFormat.allCases {
            let data = try CaptureImageEncoder.data(
                for: image,
                format: format,
                jpegQuality: 0.9
            )
            let representation = try #require(NSBitmapImageRep(data: data))
            #expect(representation.pixelsWide == 7)
            #expect(representation.pixelsHigh == 5)
        }
    }

    @Test
    func collisionSafeNameNeverSilentlyOverwrites() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapDeckTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let proposed = folder.appendingPathComponent("Capture.png")
        let second = folder.appendingPathComponent("Capture-2.png")
        try Data().write(to: proposed)
        try Data().write(to: second)

        let result = CollisionSafeFileURL.make(from: proposed)

        #expect(result.lastPathComponent == "Capture-3.png")
    }

    @Test
    func exclusiveWriterRejectsAnExistingFileWithoutCrashing() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapDeckWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appendingPathComponent("Capture.png")
        let original = Data("original".utf8)
        try CaptureDataWriter.write(original, to: target)

        #expect(throws: (any Error).self) {
            try CaptureDataWriter.write(Data("replacement".utf8), to: target)
        }
        #expect(try Data(contentsOf: target) == original)
    }

    @Test
    func outputPipelinePropagatesDiskFullAndPermissionFailures() throws {
        let context = try #require(
            CGContext(
                data: nil,
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let result = try CaptureResult(
            image: #require(context.makeImage()),
            displayID: 1,
            timestamp: Date()
        )
        let configuration = CaptureSaveConfiguration(
            format: .png,
            jpegQuality: 0.9,
            filenamePattern: "Capture",
            folderBookmark: nil
        )

        for code in [CocoaError.fileWriteOutOfSpace, CocoaError.fileWriteNoPermission] {
            #expect(throws: CocoaError.self) {
                try CaptureOutputPipeline.encodeAndWrite(
                    result,
                    to: URL(fileURLWithPath: "/unwritten/Capture.png"),
                    configuration: configuration,
                    writer: { _, _ in throw CocoaError(code) }
                )
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func fourKPNGEncodingCompletesWithinTheV1PerformanceBudget() throws {
        let context = try #require(
            CGContext(
                data: nil,
                width: 3840,
                height: 2160,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3840, height: 2160))
        let image = try #require(context.makeImage())

        let start = ContinuousClock.now
        let data = try CaptureImageEncoder.data(
            for: image,
            format: .png,
            jpegQuality: 0.9
        )
        let elapsed = start.duration(to: .now)

        #expect(!data.isEmpty)
        #expect(elapsed < .seconds(10))
    }
}

struct SelectionGeometryTests {
    @Test
    func normalizesDragInAnyDirection() {
        let rect = SelectionGeometry.normalizedRect(
            from: CGPoint(x: 90, y: 80),
            to: CGPoint(x: 10, y: 20)
        )

        #expect(rect == CGRect(x: 10, y: 20, width: 80, height: 60))
    }

    @Test
    func convertsBottomLeftRegionToScreenCaptureCoordinates() {
        let rect = SelectionGeometry.screenCaptureRect(
            from: CGRect(x: 50, y: 100, width: 300, height: 200),
            screenHeight: 900
        )

        #expect(rect == CGRect(x: 50, y: 600, width: 300, height: 200))
    }

    @Test
    func convertsQuartzWindowFrameToAppKitCoordinates() {
        let rect = SelectionGeometry.quartzRectToAppKit(
            CGRect(x: 40, y: 100, width: 500, height: 300),
            primaryScreenMaxY: 1080
        )

        #expect(rect == CGRect(x: 40, y: 680, width: 500, height: 300))
    }

    @Test
    func convertsLocalPointOnDisplayBelowPrimaryToQuartzCoordinates() {
        let point = SelectionGeometry.localAppKitPointToQuartz(
            CGPoint(x: 200, y: 300),
            displayQuartzFrame: CGRect(x: 0, y: 1080, width: 1512, height: 982)
        )

        #expect(point == CGPoint(x: 200, y: 1762))
    }

    @Test
    func convertsQuartzRectOnDisplayLeftOfPrimaryToLocalCoordinates() {
        let rect = SelectionGeometry.quartzRectToLocalAppKit(
            CGRect(x: -1000, y: 100, width: 400, height: 300),
            displayQuartzFrame: CGRect(x: -1080, y: 0, width: 1080, height: 1920)
        )

        #expect(rect == CGRect(x: 80, y: 1520, width: 400, height: 300))
    }
}

struct CapturePixelSizingTests {
    @Test
    func doublesPointDimensionsForRetinaCapture() {
        let result = CapturePixelSizing.pixels(
            for: CGSize(width: 1512, height: 982),
            scale: 2
        )

        #expect(result == CGSize(width: 3024, height: 1964))
    }

    @Test
    func keepsNativeDimensionsForStandardDensityDisplay() {
        let result = CapturePixelSizing.pixels(
            for: CGSize(width: 1920, height: 1080),
            scale: 1
        )

        #expect(result == CGSize(width: 1920, height: 1080))
    }

    @Test
    func alignsFractionalRegionToPhysicalPixelsOnStandardDisplay() {
        let result = CapturePixelSizing.pixelAlignedSourceRect(
            CGRect(x: 289.5, y: 240.5, width: 1163, height: 833),
            within: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            scale: 1
        )

        #expect(result == CGRect(x: 289, y: 240, width: 1164, height: 834))
    }

    @Test
    func alignsFractionalRegionToHalfPointsOnRetinaDisplay() {
        let result = CapturePixelSizing.pixelAlignedSourceRect(
            CGRect(x: 10.25, y: 20.25, width: 100, height: 80),
            within: CGRect(x: 0, y: 0, width: 1512, height: 982),
            scale: 2
        )

        #expect(result == CGRect(x: 10, y: 20, width: 100.5, height: 80.5))
        #expect(
            CapturePixelSizing.pixels(for: result.size, scale: 2)
                == CGSize(width: 201, height: 161)
        )
    }
}

struct CaptureThumbnailLayoutTests {
    @Test
    func sizesLandscapeThumbnailWithoutChangingAspectRatio() {
        let size = CaptureThumbnailLayout.size(
            imageSize: CGSize(width: 1920, height: 1080)
        )

        #expect(size == CGSize(width: 240, height: 135))
    }

    @Test
    func sizesPortraitThumbnailWithinTheMaximumHeight() {
        let size = CaptureThumbnailLayout.size(
            imageSize: CGSize(width: 1080, height: 1920)
        )

        #expect(size == CGSize(width: 90, height: 160))
    }

    @Test
    func anchorsThumbnailInsideTheBottomRightOfItsDisplay() {
        let origin = CaptureThumbnailLayout.origin(
            panelSize: CGSize(width: 260, height: 155),
            visibleFrame: CGRect(x: -1080, y: 24, width: 1080, height: 1896)
        )

        #expect(origin == CGPoint(x: -280, y: 44))
    }
}

@MainActor
struct AnnotationDocumentTests {
    @Test
    func rectangleIsClippedToSourceBounds() throws {
        let document = try AnnotationDocument(sourceImage: makeWhiteImage(width: 20, height: 10))

        let added = document.addRectangle(
            CGRect(x: -5, y: -2, width: 16, height: 8),
            lineWidth: 2
        )

        #expect(added)
        #expect(document.elements.count == 1)
        guard case let .rectangle(annotation) = document.elements[0] else {
            Issue.record("Expected a rectangle annotation")
            return
        }
        #expect(annotation.rect == CGRect(x: 0, y: 0, width: 11, height: 6))
    }

    @Test
    func undoRedoAndNewEditMaintainCommandHistory() throws {
        let document = try AnnotationDocument(sourceImage: makeWhiteImage(width: 40, height: 30))
        document.addRectangle(CGRect(x: 2, y: 2, width: 10, height: 8))
        document.addRectangle(CGRect(x: 15, y: 10, width: 12, height: 9))

        document.undo()
        #expect(document.elements.count == 1)
        #expect(document.canRedo)

        document.redo()
        #expect(document.elements.count == 2)
        #expect(!document.canRedo)

        document.undo()
        document.addRectangle(CGRect(x: 5, y: 15, width: 8, height: 8))
        #expect(document.elements.count == 2)
        #expect(!document.canRedo)
    }

    @Test
    func renderingKeepsDimensionsAndDrawsWithoutMutatingSource() throws {
        let source = try makeWhiteImage(width: 24, height: 18)
        let document = AnnotationDocument(sourceImage: source)
        document.addRectangle(
            CGRect(x: 2, y: 2, width: 18, height: 12),
            lineWidth: 3
        )

        let rendered = try document.renderedImage()

        #expect(rendered.width == source.width)
        #expect(rendered.height == source.height)
        #expect(redPixelCount(in: source) == 0)
        #expect(redPixelCount(in: rendered) > 0)
    }

    @Test
    func arrowAndTextRenderWithoutChangingSourceDimensions() throws {
        let source = try makeWhiteImage(width: 160, height: 100)
        let document = AnnotationDocument(sourceImage: source)

        #expect(document.addArrow(from: CGPoint(x: 12, y: 82), to: CGPoint(x: 110, y: 20)))
        let textID = document.addText(
            "CapDeck",
            in: CGRect(x: 20, y: 15, width: 120, height: 38),
            fontSize: 24
        )
        #expect(textID != nil)

        let rendered = try document.renderedImage()

        #expect(rendered.width == 160)
        #expect(rendered.height == 100)
        #expect(redPixelCount(in: rendered) > 40)
        #expect(redPixelCount(in: source) == 0)
    }

    @Test
    func textCanBeEditedDeletedAndRestored() throws {
        let document = try AnnotationDocument(sourceImage: makeWhiteImage(width: 120, height: 80))
        let textID = try #require(
            document.addText("Before", in: CGRect(x: 10, y: 10, width: 90, height: 30))
        )

        #expect(document.updateText(id: textID, text: "After"))
        guard case let .text(updated) = document.elements.first else {
            Issue.record("Expected a text annotation")
            return
        }
        #expect(updated.text == "After")

        #expect(document.deleteElement(id: textID))
        #expect(document.elements.isEmpty)
        document.undo()
        #expect(document.elements.count == 1)
        document.undo()
        guard case let .text(original) = document.elements.first else {
            Issue.record("Expected restored text")
            return
        }
        #expect(original.text == "Before")
        document.redo()
        guard case let .text(redone) = document.elements.first else {
            Issue.record("Expected redone text")
            return
        }
        #expect(redone.text == "After")
    }

    @Test
    func blurChangesOnlyTheSelectedRegion() throws {
        let source = try makeSplitImage(width: 80, height: 40)
        let document = AnnotationDocument(sourceImage: source)
        #expect(document.addBlur(CGRect(x: 32, y: 0, width: 16, height: 40), radius: 8))

        let rendered = try document.renderedImage()

        #expect(rendered.width == source.width)
        #expect(rendered.height == source.height)
        #expect(pixel(in: rendered, x: 5, y: 20) == pixel(in: source, x: 5, y: 20))
        #expect(pixel(in: rendered, x: 38, y: 20) != pixel(in: source, x: 38, y: 20))
    }

    @Test
    func cropUsesTopLeftImageCoordinatesAndParticipatesInUndoRedo() throws {
        let source = try makeQuadrantImage(width: 100, height: 80)
        let document = AnnotationDocument(sourceImage: source)

        #expect(document.setCrop(CGRect(x: 50, y: 0, width: 50, height: 40)))
        #expect(document.outputPixelSize == CGSize(width: 50, height: 40))
        let cropped = try document.renderedImage()

        #expect(cropped.width == 50)
        #expect(cropped.height == 40)
        #expect(isMostlyGreen(pixel(in: cropped, x: 25, y: 20)))

        document.undo()
        #expect(document.cropRect == nil)
        #expect(document.outputPixelSize == CGSize(width: 100, height: 80))
        document.redo()
        #expect(document.cropRect == CGRect(x: 50, y: 0, width: 50, height: 40))
    }

    @Test
    func canvasGeometryFitsAndMapsRetinaSizedImages() {
        let fitted = AnnotationCanvasGeometry.fittedRect(
            imageSize: CGSize(width: 3024, height: 1964),
            canvasSize: CGSize(width: 900, height: 700)
        )
        let center = AnnotationCanvasGeometry.imagePoint(
            from: CGPoint(x: fitted.midX, y: fitted.midY),
            fittedRect: fitted,
            imageSize: CGSize(width: 3024, height: 1964)
        )

        #expect(fitted.width == 900)
        #expect(abs(center.x - 1512) < 0.001)
        #expect(abs(center.y - 982) < 0.001)
    }

    @Test
    func canvasPointMappingClampsOutsideTheImage() {
        let fitted = CGRect(x: 50, y: 25, width: 200, height: 100)

        let point = AnnotationCanvasGeometry.imagePoint(
            from: CGPoint(x: 500, y: -100),
            fittedRect: fitted,
            imageSize: CGSize(width: 1000, height: 500)
        )

        #expect(point == CGPoint(x: 1000, y: 0))
    }

    private func makeWhiteImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func makeSplitImage(width: Int, height: Int) throws -> CGImage {
        let context = try makeContext(width: width, height: height)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        return try #require(context.makeImage())
    }

    private func makeQuadrantImage(width: Int, height: Int) throws -> CGImage {
        let context = try makeContext(width: width, height: height)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: width / 2, y: height / 2, width: width / 2, height: height / 2))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height / 2))
        return try #require(context.makeImage())
    }

    private func makeContext(width: Int, height: Int) throws -> CGContext {
        try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
    }

    private func pixel(in image: CGImage, x: Int, y: Int) -> NSColor? {
        NSBitmapImageRep(cgImage: image)
            .colorAt(x: x, y: y)?
            .usingColorSpace(.deviceRGB)
    }

    private func isMostlyGreen(_ color: NSColor?) -> Bool {
        guard let color else { return false }
        return color.greenComponent > 0.8
            && color.redComponent < 0.2
            && color.blueComponent < 0.2
    }

    private func redPixelCount(in image: CGImage) -> Int {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var count = 0
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide {
                guard
                    let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                else { continue }
                if color.redComponent > 0.8,
                   color.greenComponent < 0.4,
                   color.blueComponent < 0.4
                {
                    count += 1
                }
            }
        }
        return count
    }
}

@MainActor
struct PasteboardClipboardServiceTests {
    @Test
    func writesAReadableImageRepresentation() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("CapDeckTests.\(UUID().uuidString)")
        )
        let service = PasteboardClipboardService(pasteboard: pasteboard)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: 4,
                height: 5,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let image = try #require(context.makeImage())

        try service.write(
            CaptureResult(image: image, displayID: 1, timestamp: Date())
        )

        let pngData = try #require(pasteboard.data(forType: .png))
        let pngRepresentation = try #require(NSBitmapImageRep(data: pngData))
        #expect(pngRepresentation.pixelsWide == 4)
        #expect(pngRepresentation.pixelsHigh == 5)

        let tiffData = try #require(pasteboard.data(forType: .tiff))
        let tiffRepresentation = try #require(NSBitmapImageRep(data: tiffData))
        #expect(tiffRepresentation.pixelsWide == 4)
        #expect(tiffRepresentation.pixelsHigh == 5)
        #expect(pasteboard.types?.first == .png)
    }

    @Test
    func losslessPNGDoesNotBlendAdjacentPixels() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("CapDeckPixelTests.\(UUID().uuidString)")
        )
        let service = PasteboardClipboardService(pasteboard: pasteboard)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: 2,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.setFillColor(NSColor.green.cgColor)
        context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
        let image = try #require(context.makeImage())

        try service.write(
            CaptureResult(image: image, displayID: 1, timestamp: Date())
        )

        let pngData = try #require(pasteboard.data(forType: .png))
        let decoded = try #require(NSBitmapImageRep(data: pngData))
        let first = try #require(decoded.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        let second = try #require(decoded.colorAt(x: 1, y: 0)?.usingColorSpace(.deviceRGB))
        #expect(first.redComponent > first.greenComponent)
        #expect(first.redComponent > first.blueComponent)
        #expect(second.greenComponent > second.redComponent)
        #expect(second.greenComponent > second.blueComponent)
        #expect(first.redComponent - second.redComponent > 0.5)
        #expect(second.greenComponent - first.greenComponent > 0.4)
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
private final class GlobalShortcutRegistrarFake: GlobalShortcutRegistering {
    private let conflictingAction: GlobalShortcutAction?
    private let conflictingShortcut: GlobalShortcut?
    private var handlers: [GlobalShortcutAction: @MainActor (GlobalShortcutAction) -> Void] = [:]
    private(set) var registeredActions: [GlobalShortcutAction] = []

    init(
        conflict: GlobalShortcutAction? = nil,
        conflictingShortcut: GlobalShortcut? = nil
    ) {
        conflictingAction = conflict
        self.conflictingShortcut = conflictingShortcut
    }

    func register(
        _ action: GlobalShortcutAction,
        shortcut: GlobalShortcut,
        handler: @escaping @MainActor (GlobalShortcutAction) -> Void
    ) -> GlobalShortcutRegistrationStatus {
        registeredActions.append(action)
        guard action != conflictingAction, shortcut != conflictingShortcut else { return .conflict }
        handlers[action] = handler
        return .registered
    }

    func unregister(_ action: GlobalShortcutAction) {
        handlers[action] = nil
    }

    func trigger(_ action: GlobalShortcutAction) {
        handlers[action]?(action)
    }
}

private enum TestServiceError: Error {
    case failed
}

@MainActor
private final class LaunchAtLoginControllerFake: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus
    let registerError: Error?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSettingsCount = 0

    init(
        status: LaunchAtLoginStatus = .disabled,
        registerError: Error? = nil
    ) {
        self.status = status
        self.registerError = registerError
    }

    func register() throws {
        registerCount += 1
        if let registerError {
            throw registerError
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        status = .disabled
    }

    func openSystemSettings() {
        openSettingsCount += 1
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

@MainActor
private final class ClipboardServiceFake: ClipboardWriting {
    private(set) var writeCount = 0
    var error: Error?

    func write(_: CaptureResult) throws {
        writeCount += 1
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
