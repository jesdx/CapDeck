import Combine
import Foundation
import Sparkle

@MainActor
final class SoftwareUpdateService: ObservableObject {
    @Published private(set) var canCheckForUpdates: Bool
    @Published private(set) var automaticallyChecksForUpdates: Bool

    let displayVersion: String

    private var updaterController: SPUStandardUpdaterController?
    private let checkAction: () -> Void
    private let automaticChecksAction: (Bool) -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(startingUpdater: Bool, bundle: Bundle = .main) {
        let controller = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let updater = controller.updater

        updaterController = controller
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        displayVersion = Self.displayVersion(from: bundle)
        checkAction = { controller.checkForUpdates(nil) }
        automaticChecksAction = { enabled in
            updater.automaticallyChecksForUpdates = enabled
        }

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] automaticallyChecks in
                self?.automaticallyChecksForUpdates = automaticallyChecks
            }
            .store(in: &cancellables)
    }

    init(
        displayVersion: String,
        canCheckForUpdates: Bool,
        automaticallyChecksForUpdates: Bool,
        checkAction: @escaping () -> Void = {},
        automaticChecksAction: @escaping (Bool) -> Void = { _ in }
    ) {
        self.displayVersion = displayVersion
        self.canCheckForUpdates = canCheckForUpdates
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.checkAction = checkAction
        self.automaticChecksAction = automaticChecksAction
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        checkAction()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard automaticallyChecksForUpdates != enabled else { return }
        automaticallyChecksForUpdates = enabled
        automaticChecksAction(enabled)
    }

    private static func displayVersion(from bundle: Bundle) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "Unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "Unknown"
        return "\(version) (Build \(build))"
    }
}
