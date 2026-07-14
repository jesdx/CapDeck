import Combine
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var label: String {
        switch self {
        case .disabled: "Off"
        case .enabled: "Enabled"
        case .requiresApproval: "Approval Required"
        case .unavailable: "Requires Signed Build"
        }
    }

    var isRequested: Bool {
        self == .enabled || self == .requiresApproval
    }
}

@MainActor
protocol LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
private final class SystemLaunchAtLoginController: LaunchAtLoginControlling {
    private let service = SMAppService.mainApp

    var status: LaunchAtLoginStatus {
        switch service.status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var status: LaunchAtLoginStatus
    @Published private(set) var errorMessage: String?

    private let controller: LaunchAtLoginControlling

    init(controller: LaunchAtLoginControlling? = nil) {
        let resolvedController = controller ?? SystemLaunchAtLoginController()
        self.controller = resolvedController
        status = resolvedController.status
    }

    var isRequested: Bool {
        status.isRequested
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try controller.register()
            } else {
                try controller.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        status = controller.status
    }

    func openSystemSettings() {
        controller.openSystemSettings()
    }
}
