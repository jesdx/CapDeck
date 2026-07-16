import Carbon.HIToolbox

struct GlobalShortcut: Codable, Equatable, Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    var displayValue: String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 {
            value += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            value += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            value += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            value += "⌘"
        }
        return value + keyLabel
    }
}

enum GlobalShortcutAction: UInt32, CaseIterable, Hashable, Identifiable, Sendable {
    case captureRegion = 1
    case captureWindow = 2
    case captureFullScreen = 3
    case captureText = 4

    var id: UInt32 {
        rawValue
    }

    var title: String {
        switch self {
        case .captureRegion: "Capture Region"
        case .captureWindow: "Capture Window"
        case .captureFullScreen: "Capture Full Screen"
        case .captureText: "Capture Text"
        }
    }

    var storageKey: String {
        switch self {
        case .captureRegion: "region"
        case .captureWindow: "window"
        case .captureFullScreen: "fullScreen"
        case .captureText: "text"
        }
    }

    var defaultShortcut: GlobalShortcut {
        let modifiers = UInt32(controlKey | shiftKey)
        return switch self {
        case .captureRegion:
            GlobalShortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: modifiers, keyLabel: "J")
        case .captureWindow:
            GlobalShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: modifiers, keyLabel: "K")
        case .captureFullScreen:
            GlobalShortcut(keyCode: UInt32(kVK_ANSI_L), modifiers: modifiers, keyLabel: "L")
        case .captureText:
            GlobalShortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: modifiers, keyLabel: "T")
        }
    }
}

enum GlobalShortcutRegistrationStatus: Equatable, Sendable {
    case registered
    case conflict
    case failed(code: Int32)

    var label: String {
        switch self {
        case .registered: "Active"
        case .conflict: "Conflict"
        case .failed: "Unavailable"
        }
    }
}
