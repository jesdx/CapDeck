import Combine
import Foundation

#if canImport(AppKit)
    import AppKit
#endif

enum SavePolicy: String, CaseIterable, Sendable {
    case never
    case always
    case askEveryTime
}

enum PreviewPolicy: String, CaseIterable, Sendable {
    case always
    case never
    case autoHide
}

@MainActor
final class AppSettings: ObservableObject {
    static let currentSchemaVersion = 1
    static let menuBarVisibilityDefaultsKey = "settings.menuBarIconVisible"

    private enum Key {
        static let schemaVersion = "settings.schemaVersion"
        static let autoCopy = "settings.autoCopy"
        static let savePolicy = "settings.savePolicy"
        static let previewPolicy = "settings.previewPolicy"
        static let previewDuration = "settings.previewDuration"
        static let captureDelay = "settings.captureDelay"
        static let imageFormat = "settings.imageFormat"
        static let jpegQuality = "settings.jpegQuality"
        static let filenamePattern = "settings.filenamePattern"
        static let saveFolderBookmark = "settings.saveFolderBookmark"
        static let saveFolderDisplayName = "settings.saveFolderDisplayName"
        static let menuBarIconVisible = AppSettings.menuBarVisibilityDefaultsKey
        static let legacyAutoSave = "settings.autoSave"
        static let legacyPreviewEnabled = "settings.previewEnabled"

        static let restorable = [
            autoCopy,
            savePolicy,
            previewPolicy,
            previewDuration,
            captureDelay,
            imageFormat,
            jpegQuality,
            filenamePattern,
            saveFolderBookmark,
            saveFolderDisplayName,
            menuBarIconVisible,
        ]
    }

    private let defaults: UserDefaults

    @Published var isAutoCopyEnabled: Bool {
        didSet { defaults.set(isAutoCopyEnabled, forKey: Key.autoCopy) }
    }

    @Published var savePolicy: SavePolicy {
        didSet { defaults.set(savePolicy.rawValue, forKey: Key.savePolicy) }
    }

    @Published var previewPolicy: PreviewPolicy {
        didSet { defaults.set(previewPolicy.rawValue, forKey: Key.previewPolicy) }
    }

    @Published var previewDuration: TimeInterval {
        didSet { defaults.set(previewDuration, forKey: Key.previewDuration) }
    }

    @Published var captureDelay: TimeInterval {
        didSet { defaults.set(captureDelay, forKey: Key.captureDelay) }
    }

    @Published var imageFormat: ImageFormat {
        didSet { defaults.set(imageFormat.rawValue, forKey: Key.imageFormat) }
    }

    @Published var jpegQuality: Double {
        didSet { defaults.set(min(max(jpegQuality, 0.1), 1), forKey: Key.jpegQuality) }
    }

    @Published var filenamePattern: String {
        didSet { defaults.set(filenamePattern, forKey: Key.filenamePattern) }
    }

    @Published var isMenuBarIconVisible: Bool {
        didSet {
            defaults.set(isMenuBarIconVisible, forKey: Key.menuBarIconVisible)
            Self.applyApplicationVisibility(menuBarIconVisible: isMenuBarIconVisible)
        }
    }

    @Published private(set) var saveFolderBookmark: Data?
    @Published private(set) var saveFolderDisplayName: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrate(defaults)

        if defaults.object(forKey: Key.autoCopy) == nil {
            isAutoCopyEnabled = true
        } else {
            isAutoCopyEnabled = defaults.bool(forKey: Key.autoCopy)
        }

        savePolicy =
            SavePolicy(
                rawValue: defaults.string(forKey: Key.savePolicy) ?? ""
            ) ?? .never
        previewPolicy =
            PreviewPolicy(
                rawValue: defaults.string(forKey: Key.previewPolicy) ?? ""
            ) ?? .autoHide

        let storedDuration = defaults.double(forKey: Key.previewDuration)
        previewDuration = storedDuration > 0 ? storedDuration : 2
        captureDelay = max(0, defaults.double(forKey: Key.captureDelay))
        imageFormat =
            ImageFormat(
                rawValue: defaults.string(forKey: Key.imageFormat) ?? ""
            ) ?? .png
        let storedJPEGQuality = defaults.double(forKey: Key.jpegQuality)
        jpegQuality = storedJPEGQuality > 0 ? min(storedJPEGQuality, 1) : 0.9
        filenamePattern =
            defaults.string(forKey: Key.filenamePattern)
            ?? FilenamePattern.defaultValue
        if defaults.object(forKey: Key.menuBarIconVisible) == nil {
            isMenuBarIconVisible = true
        } else {
            isMenuBarIconVisible = defaults.bool(forKey: Key.menuBarIconVisible)
        }
        saveFolderBookmark = defaults.data(forKey: Key.saveFolderBookmark)
        saveFolderDisplayName = defaults.string(forKey: Key.saveFolderDisplayName)
    }

    var isAIWorkflowPresetActive: Bool {
        isAutoCopyEnabled
            && savePolicy == .never
            && previewPolicy == .autoHide
            && previewDuration == 2
    }

    func applyAIWorkflowPreset() {
        isAutoCopyEnabled = true
        savePolicy = .never
        previewPolicy = .autoHide
        previewDuration = 2
    }

    func restoreDefaults() {
        Key.restorable.forEach(defaults.removeObject(forKey:))
        isAutoCopyEnabled = true
        savePolicy = .never
        previewPolicy = .autoHide
        previewDuration = 2
        captureDelay = 0
        imageFormat = .png
        jpegQuality = 0.9
        filenamePattern = FilenamePattern.defaultValue
        isMenuBarIconVisible = true
        saveFolderBookmark = nil
        saveFolderDisplayName = nil
    }

    func setSaveFolder(_ url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        saveFolderBookmark = bookmark
        saveFolderDisplayName = url.path(percentEncoded: false)
        defaults.set(bookmark, forKey: Key.saveFolderBookmark)
        defaults.set(saveFolderDisplayName, forKey: Key.saveFolderDisplayName)
    }

    func clearSaveFolder() {
        saveFolderBookmark = nil
        saveFolderDisplayName = nil
        defaults.removeObject(forKey: Key.saveFolderBookmark)
        defaults.removeObject(forKey: Key.saveFolderDisplayName)
    }

    var saveConfiguration: CaptureSaveConfiguration {
        CaptureSaveConfiguration(
            format: imageFormat,
            jpegQuality: jpegQuality,
            filenamePattern: filenamePattern,
            folderBookmark: saveFolderBookmark
        )
    }

    private static func migrate(_ defaults: UserDefaults) {
        let storedVersion = defaults.integer(forKey: Key.schemaVersion)
        guard storedVersion < currentSchemaVersion else { return }

        if defaults.object(forKey: Key.savePolicy) == nil,
            defaults.object(forKey: Key.legacyAutoSave) != nil
        {
            let policy: SavePolicy =
                defaults.bool(forKey: Key.legacyAutoSave)
                ? .always
                : .never
            defaults.set(policy.rawValue, forKey: Key.savePolicy)
        }

        if defaults.object(forKey: Key.previewPolicy) == nil,
            defaults.object(forKey: Key.legacyPreviewEnabled) != nil
        {
            let policy: PreviewPolicy =
                defaults.bool(forKey: Key.legacyPreviewEnabled)
                ? .always
                : .never
            defaults.set(policy.rawValue, forKey: Key.previewPolicy)
        }

        defaults.removeObject(forKey: Key.legacyAutoSave)
        defaults.removeObject(forKey: Key.legacyPreviewEnabled)
        defaults.set(currentSchemaVersion, forKey: Key.schemaVersion)
    }

    private static func applyApplicationVisibility(menuBarIconVisible: Bool) {
        #if canImport(AppKit)
            guard NSApp != nil else { return }
            NSApp.setActivationPolicy(menuBarIconVisible ? .accessory : .regular)
            if !menuBarIconVisible {
                NSApp.activate(ignoringOtherApps: true)
            }
        #endif
    }
}
