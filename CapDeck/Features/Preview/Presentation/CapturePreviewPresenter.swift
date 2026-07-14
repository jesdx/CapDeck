import AppKit
import SwiftUI

enum CaptureThumbnailLayout {
    nonisolated static let inset: CGFloat = 20

    nonisolated static func size(
        imageSize: CGSize,
        maxWidth: CGFloat = 240,
        maxHeight: CGFloat = 160
    ) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(width: maxWidth, height: maxHeight)
        }

        let aspectRatio = imageSize.width / imageSize.height
        if aspectRatio >= maxWidth / maxHeight {
            return CGSize(
                width: maxWidth,
                height: max(72, maxWidth / aspectRatio)
            )
        }
        return CGSize(
            width: max(72, maxHeight * aspectRatio),
            height: maxHeight
        )
    }

    nonisolated static func origin(
        panelSize: CGSize,
        visibleFrame: CGRect,
        inset: CGFloat = inset
    ) -> CGPoint {
        CGPoint(
            x: visibleFrame.maxX - panelSize.width - inset,
            y: visibleFrame.minY + inset
        )
    }
}

@MainActor
protocol CapturePreviewPresenting {
    /// True while a modal save sheet is attached to the preview window (or the
    /// annotation editor it can open), so callers can avoid tearing the
    /// preview down while the user is mid-save.
    var isPresentingModalSheet: Bool { get }
    func present(
        _ result: CaptureResult,
        policy: PreviewPolicy,
        duration: TimeInterval
    )
    func presentFull(_ result: CaptureResult)
    func dismiss()
}

@MainActor
final class CapturePreviewPresenter: NSObject, CapturePreviewPresenting, NSWindowDelegate {
    private let annotationPresenter: AnnotationEditing
    private let clipboardService: ClipboardWriting
    private let displayService: DisplayProviding
    private let saveService: CaptureSaving
    private let configurationProvider: () -> CaptureSaveConfiguration
    private var thumbnailPanel: NSPanel?
    private var previewPanel: NSPanel?
    private var autoHideTask: Task<Void, Never>?

    init(
        annotationPresenter: AnnotationEditing,
        clipboardService: ClipboardWriting,
        displayService: DisplayProviding,
        saveService: CaptureSaving,
        configurationProvider: @escaping () -> CaptureSaveConfiguration
    ) {
        self.annotationPresenter = annotationPresenter
        self.clipboardService = clipboardService
        self.displayService = displayService
        self.saveService = saveService
        self.configurationProvider = configurationProvider
    }

    var isPresentingModalSheet: Bool {
        previewPanel?.attachedSheet != nil || annotationPresenter.isPresentingModalSheet
    }

    func present(
        _ result: CaptureResult,
        policy: PreviewPolicy,
        duration: TimeInterval
    ) {
        guard policy != .never else { return }
        dismiss()

        let targetDisplay = displayService.availableDisplays().first {
            $0.id == result.displayID
        }
        let displayScale = targetDisplay?.nativeScale ?? 1
        let visibleFrame =
            targetDisplay?.screen.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? CGRect(x: 0, y: 0, width: 900, height: 650)
        let thumbnailView = CaptureThumbnailView(
            image: result.image,
            onOpen: { [weak self] in
                self?.presentFullPreview(
                    result,
                    displayScale: displayScale,
                    visibleFrame: visibleFrame
                )
            }
        )

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: thumbnailView)

        let imageSize = CGSize(width: result.image.width, height: result.image.height)
        let contentSize = CaptureThumbnailLayout.size(imageSize: imageSize)
        let panelSize = CGSize(width: contentSize.width + 20, height: contentSize.height + 20)
        panel.setContentSize(panelSize)
        panel.setFrameOrigin(
            CaptureThumbnailLayout.origin(
                panelSize: panelSize,
                visibleFrame: visibleFrame
            )
        )

        thumbnailPanel = panel
        panel.orderFrontRegardless()

        if policy == .autoHide {
            autoHideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(1, duration)))
                guard !Task.isCancelled else { return }
                self?.dismissThumbnail()
            }
        }
    }

    func presentFull(_ result: CaptureResult) {
        dismiss()
        let targetDisplay = displayService.availableDisplays().first {
            $0.id == result.displayID
        }
        let visibleFrame =
            targetDisplay?.screen.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? CGRect(x: 0, y: 0, width: 900, height: 650)
        presentFullPreview(
            result,
            displayScale: targetDisplay?.nativeScale ?? 1,
            visibleFrame: visibleFrame
        )
    }

    private func presentFullPreview(
        _ result: CaptureResult,
        displayScale: CGFloat,
        visibleFrame: CGRect
    ) {
        autoHideTask?.cancel()
        autoHideTask = nil
        dismissThumbnail()

        let previewView = CapturePreviewView(
            image: result.image,
            displayScale: displayScale,
            onAnnotate: { [weak self] in
                guard let self else { return }
                dismiss()
                annotationPresenter.present(result, visibleFrame: visibleFrame)
            },
            onCopy: { [weak self] in
                guard let self else { return false }
                do {
                    try clipboardService.write(result)
                    return true
                } catch {
                    return false
                }
            },
            onSave: { [weak self] in
                guard let self else { return .failed("Preview is no longer available.") }
                return await saveService.saveAs(
                    result,
                    configuration: configurationProvider(),
                    presentingWindow: previewPanel
                )
            },
            onClose: { [weak self] in
                self?.dismiss()
            }
        )

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "CapDeck Preview"
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: previewView)
        panel.minSize = NSSize(width: 480, height: 360)

        let panelSize = NSSize(
            width: min(900, max(560, visibleFrame.width * 0.68)),
            height: min(680, max(420, visibleFrame.height * 0.68))
        )
        panel.setContentSize(panelSize)
        panel.setFrameOrigin(
            CGPoint(
                x: visibleFrame.midX - panel.frame.width / 2,
                y: visibleFrame.midY - panel.frame.height / 2
            )
        )

        previewPanel = panel
        panel.orderFrontRegardless()
    }

    func dismiss() {
        annotationPresenter.dismiss()
        autoHideTask?.cancel()
        autoHideTask = nil
        dismissThumbnail()
        let closingPreview = previewPanel
        previewPanel = nil
        safelyClose(closingPreview)
    }

    private func dismissThumbnail() {
        let closingThumbnail = thumbnailPanel
        thumbnailPanel = nil
        safelyClose(closingThumbnail)
    }

    /// SwiftUI can still have a constraint update queued when AppKit asks a
    /// hosted panel to close. Detach it from the display cycle first, then tear
    /// down the hosting view on a later main-actor turn to avoid AppKit's
    /// `_postWindowNeedsUpdateConstraints` exception.
    private func safelyClose(_ panel: NSPanel?) {
        guard let panel else { return }
        panel.delegate = nil
        panel.orderOut(nil)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            panel.contentViewController = nil
            panel.close()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let panel = sender as? NSPanel else { return true }
        if panel === previewPanel {
            previewPanel = nil
            safelyClose(panel)
            return false
        }
        if panel === thumbnailPanel {
            autoHideTask?.cancel()
            autoHideTask = nil
            thumbnailPanel = nil
            safelyClose(panel)
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingPanel = notification.object as? NSPanel else { return }
        if closingPanel === thumbnailPanel {
            autoHideTask?.cancel()
            autoHideTask = nil
            thumbnailPanel = nil
        } else if closingPanel === previewPanel {
            previewPanel = nil
        }
    }
}

@MainActor
private struct CaptureThumbnailView: View {
    let image: CGImage
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .background(Color.black.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                .padding(10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open capture preview")
        .accessibilityHint("Opens the full CapDeck preview window")
    }
}

private enum PreviewZoomMode: String, CaseIterable, Identifiable {
    case fit
    case actual

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .fit: "Fit"
        case .actual: "1:1"
        }
    }
}

enum CapturePreviewCompletionPolicy {
    nonisolated static func shouldCloseAfterCopy(succeeded: Bool) -> Bool {
        succeeded
    }

    nonisolated static func shouldCloseAfterSave(_ outcome: CaptureSaveOutcome) -> Bool {
        if case .saved = outcome {
            return true
        }
        return false
    }
}

@MainActor
private struct CapturePreviewView: View {
    let image: CGImage
    let displayScale: CGFloat
    let onAnnotate: () -> Void
    let onCopy: () -> Bool
    let onSave: () async -> CaptureSaveOutcome
    let onClose: () -> Void

    @State private var zoomMode: PreviewZoomMode = .fit
    @State private var copyStatus: String?
    @State private var saveStatus: String?
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Capture Preview")
                        .font(.headline)
                    Text("\(image.width) × \(image.height) px  •  Native source")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Zoom", selection: $zoomMode) {
                    ForEach(PreviewZoomMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 120)
                .accessibilityLabel("Preview zoom")
                .accessibilityIdentifier("preview.zoom")
            }
            .padding(12)

            Divider()

            previewCanvas

            Divider()

            HStack {
                if let copyStatus {
                    Text(copyStatus)
                        .font(.caption)
                        .foregroundStyle(copyStatus == "Copied" ? .green : .orange)
                }
                if let saveStatus {
                    Text(saveStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onAnnotate) {
                    Label("Annotate", systemImage: "pencil.tip")
                }
                .keyboardShortcut("e", modifiers: .command)
                .accessibilityLabel("Annotate capture")
                .accessibilityIdentifier("preview.annotate")

                Button {
                    Task {
                        isSaving = true
                        let outcome = await onSave()
                        isSaving = false
                        switch outcome {
                        case let .saved(url):
                            saveStatus = "Saved as \(url.lastPathComponent)"
                        case .discarded:
                            saveStatus = "Save cancelled"
                        case let .failed(message):
                            saveStatus = message
                        case .skipped:
                            saveStatus = nil
                        }
                        if CapturePreviewCompletionPolicy.shouldCloseAfterSave(outcome) {
                            onClose()
                        }
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Save…", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(isSaving)
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityLabel("Save capture")
                .accessibilityIdentifier("preview.save")

                Button {
                    let succeeded = onCopy()
                    copyStatus = succeeded ? "Copied" : "Copy failed"
                    if CapturePreviewCompletionPolicy.shouldCloseAfterCopy(
                        succeeded: succeeded
                    ) {
                        onClose()
                    }
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: .command)
                .accessibilityLabel("Copy capture")
                .accessibilityIdentifier("preview.copy")

                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("preview.close")
            }
            .padding(12)
        }
        .background(.background)
    }

    private var previewCanvas: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                if zoomMode == .fit {
                    Image(decorative: image, scale: displayScale)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(
                            width: max(1, proxy.size.width - 32),
                            height: max(1, proxy.size.height - 32)
                        )
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        Image(decorative: image, scale: displayScale)
                            .interpolation(.none)
                            .frame(
                                width: CGFloat(image.width) / max(1, displayScale),
                                height: CGFloat(image.height) / max(1, displayScale)
                            )
                            .padding(16)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Captured image, \(image.width) by \(image.height) pixels")
        }
    }
}
