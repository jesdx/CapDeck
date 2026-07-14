import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

@MainActor
protocol GlobalShortcutRegistering: AnyObject {
    func register(
        _ action: GlobalShortcutAction,
        shortcut: GlobalShortcut,
        handler: @escaping @MainActor (GlobalShortcutAction) -> Void
    ) -> GlobalShortcutRegistrationStatus
    func unregister(_ action: GlobalShortcutAction)
}

@MainActor
final class GlobalShortcutService: ObservableObject {
    @Published private(set) var statuses: [GlobalShortcutAction: GlobalShortcutRegistrationStatus] = [:]
    @Published private(set) var shortcuts: [GlobalShortcutAction: GlobalShortcut]
    @Published private(set) var errors: [GlobalShortcutAction: String] = [:]

    private var registrar: GlobalShortcutRegistering?
    private let actionHandler: @MainActor (GlobalShortcutAction) -> Void
    private let defaults: UserDefaults
    private var hasStarted = false
    private var registrationPaused = false
    nonisolated(unsafe) private var launchObserver: NSObjectProtocol?

    init(
        registrar: GlobalShortcutRegistering? = nil,
        defaults: UserDefaults = .standard,
        actionHandler: @escaping @MainActor (GlobalShortcutAction) -> Void
    ) {
        self.registrar = registrar
        self.defaults = defaults
        self.actionHandler = actionHandler
        shortcuts = Dictionary(
            uniqueKeysWithValues: GlobalShortcutAction.allCases.map { action in
                (action, Self.loadShortcut(for: action, defaults: defaults))
            }
        )
    }

    deinit {
        if let launchObserver {
            NotificationCenter.default.removeObserver(launchObserver)
        }
    }

    func startWhenApplicationIsReady() {
        guard !hasStarted, launchObserver == nil else { return }

        if NSApplication.shared.isRunning {
            start()
            return
        }

        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.start()
            }
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        if let launchObserver {
            NotificationCenter.default.removeObserver(launchObserver)
            self.launchObserver = nil
        }

        let resolvedRegistrar = registrar ?? CarbonGlobalShortcutRegistrar()
        registrar = resolvedRegistrar
        registerAll(using: resolvedRegistrar)
    }

    func shortcut(for action: GlobalShortcutAction) -> GlobalShortcut {
        shortcuts[action] ?? action.defaultShortcut
    }

    @discardableResult
    func setShortcut(_ shortcut: GlobalShortcut, for action: GlobalShortcutAction) -> Bool {
        if GlobalShortcutAction.allCases.contains(where: {
            $0 != action && self.shortcut(for: $0) == shortcut
        }) {
            errors[action] = "Already used by another CapDeck action."
            return false
        }

        let previous = self.shortcut(for: action)
        guard previous != shortcut else {
            errors[action] = nil
            return true
        }

        guard hasStarted, let registrar else {
            shortcuts[action] = shortcut
            persist(shortcut, for: action)
            errors[action] = nil
            return true
        }

        if registrationPaused {
            let status = register(action, shortcut: shortcut, using: registrar)
            registrar.unregister(action)
            guard status == .registered else {
                errors[action] =
                    status == .conflict
                    ? "That shortcut is already in use."
                    : "macOS could not register that shortcut."
                return false
            }

            shortcuts[action] = shortcut
            errors[action] = nil
            persist(shortcut, for: action)
            return true
        }

        registrar.unregister(action)
        let status = register(action, shortcut: shortcut, using: registrar)
        guard status == .registered else {
            let restoredStatus = register(action, shortcut: previous, using: registrar)
            statuses[action] = restoredStatus
            errors[action] =
                status == .conflict
                ? "That shortcut is already in use."
                : "macOS could not register that shortcut."
            return false
        }

        shortcuts[action] = shortcut
        statuses[action] = status
        errors[action] = nil
        persist(shortcut, for: action)
        return true
    }

    func restoreDefaults() {
        let resolvedRegistrar = registrar
        if let resolvedRegistrar {
            GlobalShortcutAction.allCases.forEach(resolvedRegistrar.unregister)
        }

        shortcuts = Dictionary(
            uniqueKeysWithValues: GlobalShortcutAction.allCases.map { ($0, $0.defaultShortcut) }
        )
        errors.removeAll()

        for action in GlobalShortcutAction.allCases {
            defaults.removeObject(forKey: persistenceKey(for: action))
        }

        if hasStarted, let resolvedRegistrar {
            registerAll(using: resolvedRegistrar)
        }
    }

    func pauseRegistrationForRecording() {
        guard hasStarted, !registrationPaused, let registrar else { return }
        registrationPaused = true
        GlobalShortcutAction.allCases.forEach(registrar.unregister)
        statuses.removeAll()
    }

    func resumeRegistrationAfterRecording() {
        guard hasStarted, registrationPaused, let registrar else { return }
        registrationPaused = false
        registerAll(using: registrar)
    }

    func status(for action: GlobalShortcutAction) -> GlobalShortcutRegistrationStatus? {
        statuses[action]
    }

    private func registerAll(using registrar: GlobalShortcutRegistering) {
        for action in GlobalShortcutAction.allCases {
            statuses[action] = register(
                action,
                shortcut: shortcut(for: action),
                using: registrar
            )
        }
    }

    private func register(
        _ action: GlobalShortcutAction,
        shortcut: GlobalShortcut,
        using registrar: GlobalShortcutRegistering
    ) -> GlobalShortcutRegistrationStatus {
        registrar.register(action, shortcut: shortcut) { [weak self] action in
            self?.actionHandler(action)
        }
    }

    private func persist(_ shortcut: GlobalShortcut, for action: GlobalShortcutAction) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: persistenceKey(for: action))
    }

    private func persistenceKey(for action: GlobalShortcutAction) -> String {
        "shortcuts.\(action.storageKey)"
    }

    private static func loadShortcut(
        for action: GlobalShortcutAction,
        defaults: UserDefaults
    ) -> GlobalShortcut {
        let key = "shortcuts.\(action.storageKey)"
        guard
            let data = defaults.data(forKey: key),
            let shortcut = try? JSONDecoder().decode(GlobalShortcut.self, from: data)
        else {
            return action.defaultShortcut
        }
        return shortcut
    }
}

@MainActor
private final class CarbonGlobalShortcutRegistrar: GlobalShortcutRegistering {
    private static let signature: OSType = 0x4C58484B  // LXHK

    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    nonisolated(unsafe) private var hotKeys: [GlobalShortcutAction: EventHotKeyRef] = [:]
    nonisolated(unsafe) private var installationStatus = OSStatus(eventNotHandledErr)
    private var handlers: [GlobalShortcutAction: @MainActor (GlobalShortcutAction) -> Void] = [:]

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()

        installationStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard result == noErr,
                    hotKeyID.signature == CarbonGlobalShortcutRegistrar.signature
                else {
                    return result
                }

                let registrar = Unmanaged<CarbonGlobalShortcutRegistrar>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                MainActor.assumeIsolated {
                    registrar.deliver(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandler
        )
    }

    deinit {
        for hotKey in hotKeys.values {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register(
        _ action: GlobalShortcutAction,
        shortcut: GlobalShortcut,
        handler: @escaping @MainActor (GlobalShortcutAction) -> Void
    ) -> GlobalShortcutRegistrationStatus {
        guard installationStatus == noErr, eventHandler != nil else {
            return .failed(code: installationStatus)
        }

        var hotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        let result = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )

        guard result == noErr, let hotKey else {
            if result == eventHotKeyExistsErr {
                return .conflict
            }
            return .failed(code: result)
        }

        hotKeys[action] = hotKey
        handlers[action] = handler
        return .registered
    }

    func unregister(_ action: GlobalShortcutAction) {
        if let hotKey = hotKeys.removeValue(forKey: action) {
            UnregisterEventHotKey(hotKey)
        }
        handlers[action] = nil
    }

    private func deliver(id: UInt32) {
        guard let action = GlobalShortcutAction(rawValue: id) else { return }
        handlers[action]?(action)
    }
}
