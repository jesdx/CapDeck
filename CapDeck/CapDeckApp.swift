import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var isUITesting: Bool {
        ProcessInfo.processInfo.environment["CAPDECK_UI_TESTING"] == "1"
    }

    func applicationWillFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(isUITesting ? .regular : .accessory)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func applicationShouldRestoreApplicationState(_: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_: Notification) {
        if isUITesting {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let defaults = UserDefaults.standard
        let isVisible =
            defaults.object(
                forKey: AppSettings.menuBarVisibilityDefaultsKey
            ) == nil || defaults.bool(forKey: AppSettings.menuBarVisibilityDefaultsKey)
        NSApp.setActivationPolicy(isVisible ? .accessory : .regular)
    }

    func applicationShouldSaveApplicationState(_: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard !flag else { return true }
        let isMenuBarIconVisible =
            UserDefaults.standard.object(
                forKey: AppSettings.menuBarVisibilityDefaultsKey
            ) == nil
            || UserDefaults.standard.bool(
                forKey: AppSettings.menuBarVisibilityDefaultsKey
            )
        guard !isMenuBarIconVisible else { return false }

        DispatchQueue.main.async {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        return true
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              !(window is NSPanel)
        else {
            return
        }
        if isUITesting {
            NSApp.setActivationPolicy(.regular)
            return
        }
        let defaults = UserDefaults.standard
        let isVisible =
            defaults.object(
                forKey: AppSettings.menuBarVisibilityDefaultsKey
            ) == nil || defaults.bool(forKey: AppSettings.menuBarVisibilityDefaultsKey)
        NSApp.setActivationPolicy(isVisible ? .accessory : .regular)
    }
}

@main
struct CapDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var dependencies = DependencyContainer()

    var body: some Scene {
        MenuBarExtra(
            isInserted: Binding(
                get: { dependencies.settings.isMenuBarIconVisible },
                set: { dependencies.settings.isMenuBarIconVisible = $0 }
            )
        ) {
            MenuBarContentView(
                coordinator: dependencies.captureCoordinator,
                settings: dependencies.settings,
                globalShortcuts: dependencies.globalShortcuts,
                historyStore: dependencies.historyStore,
                historyPresenter: dependencies.historyPresenter
            )
        } label: {
            Image("CapDeckMenuBarLogo")
                .renderingMode(.template)
                .accessibilityLabel("CapDeck")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(
                settings: dependencies.settings,
                globalShortcuts: dependencies.globalShortcuts,
                launchAtLogin: dependencies.launchAtLogin,
                softwareUpdate: dependencies.softwareUpdate
            )
        }
    }
}
