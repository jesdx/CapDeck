import AppKit
import SwiftUI

@MainActor
protocol CaptureHistoryPresenting: AnyObject {
    /// True while a modal save sheet is attached to the history window, so
    /// callers can avoid tearing it down while the user is mid-save.
    var isPresentingModalSheet: Bool { get }
    func present()
    func dismiss()
}

@MainActor
final class CaptureHistoryPresenter: NSObject, CaptureHistoryPresenting, NSWindowDelegate {
    let store: CaptureHistoryStore

    private let clipboardService: ClipboardWriting
    private let previewPresenter: CapturePreviewPresenting
    private let saveService: CaptureSaving
    private let configurationProvider: () -> CaptureSaveConfiguration
    private var historyPanel: NSPanel?

    init(
        store: CaptureHistoryStore,
        clipboardService: ClipboardWriting,
        previewPresenter: CapturePreviewPresenting,
        saveService: CaptureSaving,
        configurationProvider: @escaping () -> CaptureSaveConfiguration
    ) {
        self.store = store
        self.clipboardService = clipboardService
        self.previewPresenter = previewPresenter
        self.saveService = saveService
        self.configurationProvider = configurationProvider
    }

    var isPresentingModalSheet: Bool {
        historyPanel?.attachedSheet != nil
    }

    func present() {
        if let historyPanel {
            NSApp.activate(ignoringOtherApps: true)
            historyPanel.makeKeyAndOrderFront(nil)
            return
        }

        let view = CaptureHistoryView(
            store: store,
            onPreview: { [weak self] result in
                self?.previewPresenter.presentFull(result)
            },
            onCopy: { [weak self] result in
                guard let self else { return "History is no longer available" }
                do {
                    try clipboardService.write(result)
                    return "Copied \(result.pixelWidth) × \(result.pixelHeight)"
                } catch {
                    return error.localizedDescription
                }
            },
            onSave: { [weak self] result in
                guard let self else { return "History is no longer available" }
                let outcome = await saveService.saveAs(
                    result,
                    configuration: configurationProvider(),
                    presentingWindow: historyPanel
                )
                return switch outcome {
                case let .saved(url): "Saved as \(url.lastPathComponent)"
                case .discarded: "Save cancelled"
                case let .failed(message): message
                case .skipped: "Save skipped"
                }
            },
            onClose: { [weak self] in
                self?.dismiss()
            }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "CapDeck History"
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: view)
        panel.minSize = NSSize(width: 620, height: 440)
        panel.setContentSize(NSSize(width: 760, height: 580))
        let targetFrame =
            NSScreen.screens.first {
                $0.frame.contains(NSEvent.mouseLocation)
            }?.visibleFrame ?? NSScreen.main?.visibleFrame
        if let targetFrame {
            panel.setFrameOrigin(
                CGPoint(
                    x: targetFrame.midX - panel.frame.width / 2,
                    y: targetFrame.midY - panel.frame.height / 2
                )
            )
        } else {
            panel.center()
        }

        historyPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        let closingPanel = historyPanel
        historyPanel = nil
        guard let closingPanel else { return }
        closingPanel.delegate = nil
        closingPanel.orderOut(nil)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            closingPanel.contentViewController = nil
            closingPanel.close()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let panel = sender as? NSPanel, panel === historyPanel else { return true }
        dismiss()
        return false
    }
}

@MainActor
private struct CaptureHistoryView: View {
    @ObservedObject var store: CaptureHistoryStore
    let onPreview: (CaptureResult) -> Void
    let onCopy: (CaptureResult) -> String
    let onSave: (CaptureResult) async -> String
    let onClose: () -> Void

    @State private var statusText = "History stays in memory until CapDeck quits."
    @State private var savingEntryID: UUID?
    @State private var isConfirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.entries.isEmpty {
                ContentUnavailableView(
                    "No Captures Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("New captures appear here for this app session only.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.entries) { entry in
                            historyRow(entry)
                        }
                    }
                    .padding(16)
                }
            }

            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 440)
        .background(.background)
        .confirmationDialog(
            "Clear all in-memory capture history?",
            isPresented: $isConfirmingClear
        ) {
            Button("Clear History", role: .destructive) {
                store.clear()
                statusText = "History cleared"
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved image files are not deleted.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Capture History")
                    .font(.headline)
                Text("Session only · up to \(store.maximumCount) captures · no hidden files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(store.entries.count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(store.entries.count) history items")
            Button("Clear…", role: .destructive) {
                isConfirmingClear = true
            }
            .disabled(store.entries.isEmpty)
            .accessibilityLabel("Clear capture history")
            .accessibilityIdentifier("history.clear")
        }
        .padding(16)
    }

    private func historyRow(_ entry: CaptureHistoryEntry) -> some View {
        HStack(spacing: 14) {
            Image(decorative: entry.result.image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 150, height: 92)
                .background(Color(nsColor: .underPageBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.result.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                    .font(.headline)
                Text("\(entry.result.pixelWidth) × \(entry.result.pixelHeight) px")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let savedURL = entry.savedURL {
                    Label(savedURL.lastPathComponent, systemImage: "externaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Label("Memory only", systemImage: "memorychip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Button("Preview") {
                        onPreview(entry.result)
                    }
                    .accessibilityLabel("Preview history capture")
                    .accessibilityIdentifier("history.preview.\(entry.id)")

                    Button("Copy") {
                        statusText = onCopy(entry.result)
                    }
                    .accessibilityLabel("Copy history capture")
                    .accessibilityIdentifier("history.copy.\(entry.id)")

                    Button {
                        Task {
                            savingEntryID = entry.id
                            statusText = await onSave(entry.result)
                            savingEntryID = nil
                        }
                    } label: {
                        if savingEntryID == entry.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Save As…")
                        }
                    }
                    .disabled(savingEntryID != nil)
                    .accessibilityLabel("Save history capture")
                    .accessibilityIdentifier("history.save.\(entry.id)")
                }

                Button("Remove", role: .destructive) {
                    store.remove(id: entry.id)
                    statusText = "History item removed"
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove history capture")
                .accessibilityIdentifier("history.remove.\(entry.id)")
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Capture \(entry.result.pixelWidth) by \(entry.result.pixelHeight), \(entry.result.timestamp.formatted())"
        )
    }

    private var footer: some View {
        HStack {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text("RAM: \(ByteCountFormatter.string(fromByteCount: Int64(store.estimatedPixelBytes), countStyle: .memory))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close capture history")
                .accessibilityIdentifier("history.close")
        }
        .padding(12)
    }
}
