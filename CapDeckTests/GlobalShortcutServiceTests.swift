@testable import CapDeck
import Carbon.HIToolbox
import Foundation
import Testing

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
