import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

struct ShortcutRecorderField: View {
    let shortcut: GlobalShortcut
    let isDisabled: Bool
    let onRecord: (GlobalShortcut) -> Void
    let onRecordingChanged: (Bool) -> Void

    @StateObject private var recorder = ShortcutRecorderController()

    var body: some View {
        Button {
            recorder.start(
                onRecord: onRecord,
                onEnd: { onRecordingChanged(false) }
            )
            onRecordingChanged(true)
        } label: {
            Text(recorder.isRecording ? "Press shortcut…" : shortcut.displayValue)
                .monospaced()
                .frame(minWidth: 100)
        }
        .disabled(isDisabled)
        .help("Click, then press a shortcut. Press Escape to cancel.")
        .accessibilityLabel("Shortcut \(shortcut.displayValue)")
        .accessibilityHint("Press to record a new shortcut. Escape cancels recording.")
        .onDisappear {
            recorder.cancel()
        }
    }
}

@MainActor
private final class ShortcutRecorderController: ObservableObject {
    @Published private(set) var isRecording = false
    private nonisolated(unsafe) var monitor: Any?
    private var onRecord: ((GlobalShortcut) -> Void)?
    private var onEnd: (() -> Void)?

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func start(
        onRecord: @escaping (GlobalShortcut) -> Void,
        onEnd: @escaping () -> Void
    ) {
        cancel(notify: false)
        self.onRecord = onRecord
        self.onEnd = onEnd
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
            return nil
        }
    }

    func cancel() {
        cancel(notify: true)
    }

    private func cancel(notify: Bool) {
        let completion = notify && isRecording ? onEnd : nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        onRecord = nil
        onEnd = nil
        isRecording = false
        completion?()
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            cancel()
            return
        }

        guard let shortcut = Self.shortcut(from: event) else {
            NSSound.beep()
            return
        }

        let completion = onRecord
        let end = onEnd
        cancel(notify: false)
        completion?(shortcut)
        end?()
    }

    private static func shortcut(from event: NSEvent) -> GlobalShortcut? {
        let flags = event.modifierFlags.intersection([
            .command,
            .control,
            .option,
            .shift,
        ])
        guard !flags.isEmpty, let keyLabel = keyLabel(for: event) else { return nil }

        var modifiers: UInt32 = 0
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }

        return GlobalShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            keyLabel: keyLabel
        )
    }

    private static func keyLabel(for event: NSEvent) -> String? {
        if let functionKey = functionKeyLabel(for: Int(event.keyCode)) {
            return functionKey
        }

        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        default:
            guard let value = event.charactersIgnoringModifiers?.uppercased(),
                  !value.isEmpty
            else {
                return nil
            }
            return value
        }
    }

    private static func functionKeyLabel(for keyCode: Int) -> String? {
        let codes = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5,
            kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
            kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        guard let index = codes.firstIndex(of: keyCode) else { return nil }
        return "F\(index + 1)"
    }
}
