@testable import CapDeck
import Testing

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
