//
//  MenuBarContentView.swift
//  CapDeck
//
//  Created by Jesdaporn Saengseengam on 14/7/2569 BE.
//

import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var coordinator: CaptureCoordinator
    @ObservedObject var settings: AppSettings
    @ObservedObject var globalShortcuts: GlobalShortcutService
    @ObservedObject var historyStore: CaptureHistoryStore
    let historyPresenter: CaptureHistoryPresenting

    var body: some View {
        Group {
            Button(action: coordinator.resetStatus) {
                Label(
                    coordinator.state.statusText,
                    systemImage: coordinator.state.statusSymbol
                )
            }
            .disabled(coordinator.state == .idle || coordinator.state.isBusy)

            if coordinator.state == .permissionDenied {
                Button(action: coordinator.openPermissionSettings) {
                    Label("Open Screen Recording Settings", systemImage: "gear")
                }
            }

            Divider()

            Button {
                Task {
                    await coordinator.captureRegion()
                }
            } label: {
                shortcutLabel("Capture Region", systemImage: "viewfinder", action: .captureRegion)
            }
            .disabled(coordinator.state.isBusy)

            Menu {
                if coordinator.availableWindows.isEmpty {
                    Text("No Capturable Windows")
                } else {
                    ForEach(coordinator.availableWindows) { window in
                        Button(window.displayName) {
                            Task {
                                await coordinator.captureWindow(windowID: window.id)
                            }
                        }
                    }
                }

                Divider()

                Button {
                    coordinator.refreshAvailableWindows()
                } label: {
                    Label("Refresh Window List", systemImage: "arrow.clockwise")
                }

                Button {
                    Task {
                        await coordinator.captureWindow()
                    }
                } label: {
                    Label("Select Visually…", systemImage: "viewfinder")
                }
            } label: {
                shortcutLabel("Capture Window", systemImage: "macwindow", action: .captureWindow)
            }
            .disabled(coordinator.state.isBusy)

            Button {
                Task {
                    await coordinator.captureFullScreen()
                }
            } label: {
                shortcutLabel(
                    "Capture Full Screen",
                    systemImage: "rectangle.inset.filled",
                    action: .captureFullScreen
                )
            }
            .disabled(coordinator.state.isBusy)

            Divider()

            Toggle(isOn: $settings.isAutoCopyEnabled) {
                Label("Auto Copy", systemImage: "doc.on.clipboard")
            }

            Picker("Capture Delay", selection: $settings.captureDelay) {
                Text("No Delay").tag(TimeInterval.zero)
                Text("3 Seconds").tag(TimeInterval(3))
                Text("5 Seconds").tag(TimeInterval(5))
            }

            Menu("After Capture") {
                Button {
                    settings.applyAIWorkflowPreset()
                } label: {
                    Label(
                        settings.isAIWorkflowPresetActive
                            ? "AI Workflow Preset — Active"
                            : "Use AI Workflow Preset",
                        systemImage: settings.isAIWorkflowPresetActive
                            ? "checkmark.circle.fill"
                            : "sparkles"
                    )
                }

                Divider()

                Picker("Save", selection: $settings.savePolicy) {
                    Text("Never Save").tag(SavePolicy.never)
                    Text("Always Save").tag(SavePolicy.always)
                    Text("Ask Every Time").tag(SavePolicy.askEveryTime)
                }

                Picker("Preview", selection: $settings.previewPolicy) {
                    Text("Always").tag(PreviewPolicy.always)
                    Text("Never").tag(PreviewPolicy.never)
                    Text("Auto Hide").tag(PreviewPolicy.autoHide)
                }
            }

            Divider()

            Button {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)

            Button(action: historyPresenter.present) {
                Label(
                    historyStore.entries.isEmpty
                        ? "Capture History"
                        : "Capture History (\(historyStore.entries.count))",
                    systemImage: "clock.arrow.circlepath"
                )
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Divider()

            Button("Quit CapDeck") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .onAppear {
            coordinator.refreshAvailableWindows()
        }
    }

    private func shortcutLabel(
        _ title: String,
        systemImage: String,
        action: GlobalShortcutAction
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(shortcutMenuValue(for: action))
                .foregroundStyle(.secondary)
        }
    }

    private func shortcutMenuValue(for action: GlobalShortcutAction) -> String {
        guard let status = globalShortcuts.status(for: action) else { return "Checking…" }
        return status == .registered
            ? globalShortcuts.shortcut(for: action).displayValue
            : status.label
    }

}

#Preview {
    let dependencies = DependencyContainer()
    MenuBarContentView(
        coordinator: dependencies.captureCoordinator,
        settings: dependencies.settings,
        globalShortcuts: dependencies.globalShortcuts,
        historyStore: dependencies.historyStore,
        historyPresenter: dependencies.historyPresenter
    )
}
