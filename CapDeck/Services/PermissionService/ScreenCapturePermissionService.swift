import AppKit
import CoreGraphics

enum ScreenCapturePermissionRequestResult: Equatable {
    case authorized
    case systemPromptPresented
    case previouslyRequested
}

@MainActor
protocol ScreenCapturePermissionProviding {
    var isAuthorized: Bool { get }
    func requestAccess() -> ScreenCapturePermissionRequestResult
    func presentRecoveryPrompt()
    func openSystemSettings()
}

@MainActor
final class ScreenCapturePermissionService: ScreenCapturePermissionProviding {
    private static let requestAttemptedKey = "permissions.screenCaptureRequestAttempted"

    private let defaults: UserDefaults
    private let preflightAccess: () -> Bool
    private let requestSystemAccess: () -> Bool
    private var isPresentingRecoveryPrompt = false

    init(
        defaults: UserDefaults = .standard,
        preflightAccess: @escaping () -> Bool = CGPreflightScreenCaptureAccess,
        requestSystemAccess: @escaping () -> Bool = CGRequestScreenCaptureAccess
    ) {
        self.defaults = defaults
        self.preflightAccess = preflightAccess
        self.requestSystemAccess = requestSystemAccess
    }

    var isAuthorized: Bool {
        preflightAccess()
    }

    func requestAccess() -> ScreenCapturePermissionRequestResult {
        if isAuthorized {
            return .authorized
        }

        // CGRequestScreenCaptureAccess presents a system prompt. Calling it on
        // every capture attempt can stack prompts and make the app unusable.
        // Remember that the request was made and use the recovery path on later
        // attempts instead.
        guard !defaults.bool(forKey: Self.requestAttemptedKey) else {
            return .previouslyRequested
        }

        defaults.set(true, forKey: Self.requestAttemptedKey)
        return requestSystemAccess() ? .authorized : .systemPromptPresented
    }

    func presentRecoveryPrompt() {
        guard !isPresentingRecoveryPrompt else { return }
        isPresentingRecoveryPrompt = true
        defer { isPresentingRecoveryPrompt = false }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "CapDeck Needs Screen Recording Access"
        alert.informativeText =
            "Allow CapDeck in Privacy & Security to capture regions, windows, and displays. Reopen the app after granting access."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")

        if alert.runModal() == .alertFirstButtonReturn {
            openSystemSettings()
        }
    }

    func openSystemSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            )
        else { return }

        NSWorkspace.shared.open(url)
    }
}
