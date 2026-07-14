import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var globalShortcuts: GlobalShortcutService
    @ObservedObject var launchAtLogin: LaunchAtLoginService
    @ObservedObject var softwareUpdate: SoftwareUpdateService
    @State private var recordingAction: GlobalShortcutAction?
    @State private var saveFolderError: String?
    @State private var isConfirmingRestore = false

    var body: some View {
        TabView {
            generalPane
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            capturePane
                .tabItem {
                    Label("Capture", systemImage: "camera.viewfinder")
                }

            shortcutsPane
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            afterCapturePane
                .tabItem {
                    Label("After Capture", systemImage: "sparkles.rectangle.stack")
                }
        }
        .frame(width: 600, height: 520)
        .navigationTitle("CapDeck Settings")
        .onAppear {
            launchAtLogin.refresh()
        }
        .confirmationDialog(
            "Restore every CapDeck setting?",
            isPresented: $isConfirmingRestore
        ) {
            Button("Restore All Defaults", role: .destructive) {
                settings.restoreDefaults()
                globalShortcuts.restoreDefaults()
                saveFolderError = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets capture, saving, preview, and shortcut settings. Existing image files are not deleted.")
        }
    }

    private var generalPane: some View {
        Form {
            Section("AI Workflow") {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Clipboard-first preset")
                            .font(.headline)
                        Text("Auto Copy, Never Save, and a two-second preview.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if settings.isAIWorkflowPresetActive {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Use Preset") {
                            settings.applyAIWorkflowPreset()
                        }
                    }
                }
            }

            Section("System") {
                Toggle(
                    "Show CapDeck in the menu bar",
                    isOn: $settings.isMenuBarIconVisible
                )
                Text(
                    settings.isMenuBarIconVisible
                        ? "The Dock icon stays hidden while the menu bar icon is available."
                        : "The Dock icon remains available so Settings and Quit are never hidden."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Toggle(
                    "Launch CapDeck at login",
                    isOn: Binding(
                        get: { launchAtLogin.isRequested },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                .disabled(launchAtLogin.status == .unavailable)

                HStack {
                    Text("Login item status")
                    Spacer()
                    Text(launchAtLogin.status.label)
                        .foregroundStyle(
                            launchAtLogin.status == .requiresApproval ? .orange : .secondary
                        )
                }

                if launchAtLogin.status == .requiresApproval {
                    Button("Open Login Items Settings…") {
                        launchAtLogin.openSystemSettings()
                    }
                }

                if launchAtLogin.status == .unavailable {
                    Text("Launch at Login becomes available when CapDeck is signed with an Apple Developer identity.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = launchAtLogin.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Defaults") {
                Button("Restore All Defaults…", role: .destructive) {
                    isConfirmingRestore = true
                }
                Text("This does not delete captures already saved on disk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Software Updates") {
                HStack {
                    Text("Current version")
                    Spacer()
                    Text(softwareUpdate.displayVersion)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Toggle(
                    "Automatically check for updates",
                    isOn: Binding(
                        get: { softwareUpdate.automaticallyChecksForUpdates },
                        set: { softwareUpdate.setAutomaticallyChecksForUpdates($0) }
                    )
                )

                Button("Check for Updates…", action: softwareUpdate.checkForUpdates)
                    .disabled(!softwareUpdate.canCheckForUpdates)

                Text("Automatic checks run at most once per day. CapDeck always asks before installing an update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var capturePane: some View {
        Form {
            Section("Capture") {
                Picker("Delay", selection: $settings.captureDelay) {
                    Text("None").tag(TimeInterval.zero)
                    Text("3 Seconds").tag(TimeInterval(3))
                    Text("5 Seconds").tag(TimeInterval(5))
                }
            }

            Section("File Saving") {
                HStack {
                    Text("Folder")
                    Spacer()
                    Text(settings.saveFolderDisplayName ?? "Not selected")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 270, alignment: .trailing)
                    Button("Choose…", action: chooseSaveFolder)
                    if settings.saveFolderBookmark != nil {
                        Button("Clear") {
                            settings.clearSaveFolder()
                        }
                    }
                }

                Picker("Format", selection: $settings.imageFormat) {
                    ForEach(ImageFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                if settings.imageFormat == .jpeg {
                    HStack {
                        Slider(value: $settings.jpegQuality, in: 0.1...1, step: 0.05) {
                            Text("JPEG Quality")
                        }
                        Text("\(Int(settings.jpegQuality * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 42)
                    }
                }

                TextField("Filename pattern", text: $settings.filenamePattern)
                Text("Tokens: {date}, {time}, {timestamp}")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let patternError = FilenamePattern.validate(settings.filenamePattern) {
                    Text(patternError.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let saveFolderError {
                    Text(saveFolderError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutsPane: some View {
        Form {
            Section("Global Shortcuts") {
                ForEach(GlobalShortcutAction.allCases) { action in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(action.title)
                            Spacer()
                            ShortcutRecorderField(
                                shortcut: globalShortcuts.shortcut(for: action),
                                isDisabled: recordingAction != nil && recordingAction != action,
                                onRecord: { shortcut in
                                    globalShortcuts.setShortcut(shortcut, for: action)
                                },
                                onRecordingChanged: { isRecording in
                                    if isRecording {
                                        recordingAction = action
                                        globalShortcuts.pauseRegistrationForRecording()
                                    } else {
                                        recordingAction = nil
                                        globalShortcuts.resumeRegistrationAfterRecording()
                                    }
                                }
                            )
                            shortcutStatus(for: action)
                        }
                        if let error = globalShortcuts.errors[action] {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Button("Restore Shortcut Defaults") {
                    globalShortcuts.restoreDefaults()
                }
                Text("Shortcuts work from any app and do not require Accessibility access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var afterCapturePane: some View {
        Form {
            Section("Clipboard") {
                Toggle("Copy captures to the clipboard", isOn: $settings.isAutoCopyEnabled)
            }

            Section("Saving") {
                Picker("Save", selection: $settings.savePolicy) {
                    Text("Never").tag(SavePolicy.never)
                    Text("Always").tag(SavePolicy.always)
                    Text("Ask Every Time").tag(SavePolicy.askEveryTime)
                }

                if settings.savePolicy == .always && settings.saveFolderBookmark == nil {
                    Label("Choose a folder in Capture settings before using Always Save.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Preview") {
                Picker("Preview", selection: $settings.previewPolicy) {
                    Text("Always").tag(PreviewPolicy.always)
                    Text("Never").tag(PreviewPolicy.never)
                    Text("Auto Hide").tag(PreviewPolicy.autoHide)
                }

                if settings.previewPolicy == .autoHide {
                    Picker("Auto-hide after", selection: $settings.previewDuration) {
                        Text("2 Seconds").tag(TimeInterval(2))
                        Text("3 Seconds").tag(TimeInterval(3))
                        Text("5 Seconds").tag(TimeInterval(5))
                        Text("10 Seconds").tag(TimeInterval(10))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose CapDeck Save Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try settings.setSaveFolder(url)
                saveFolderError = nil
            } catch {
                saveFolderError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func shortcutStatus(for action: GlobalShortcutAction) -> some View {
        let status = globalShortcuts.status(for: action)
        Label(
            status?.label ?? "Checking",
            systemImage: status == .registered
                ? "checkmark.circle.fill"
                : "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(status == .registered ? .green : .orange)
    }
}
