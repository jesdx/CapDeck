@testable import CapDeck
import Foundation
import Testing

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
