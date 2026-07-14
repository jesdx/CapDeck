import AppKit
import SwiftUI

@MainActor
protocol AnnotationEditing {
    /// True while a modal save sheet is attached to the editor window, so
    /// callers can avoid tearing the editor down mid-interaction.
    var isPresentingModalSheet: Bool { get }
    func present(_ result: CaptureResult, visibleFrame: CGRect)
    func dismiss()
}

@MainActor
final class AnnotationEditorPresenter: NSObject, AnnotationEditing, NSWindowDelegate {
    private let clipboardService: ClipboardWriting
    private let saveService: CaptureSaving
    private let configurationProvider: () -> CaptureSaveConfiguration
    private var editorPanel: NSPanel?

    init(
        clipboardService: ClipboardWriting,
        saveService: CaptureSaving,
        configurationProvider: @escaping () -> CaptureSaveConfiguration
    ) {
        self.clipboardService = clipboardService
        self.saveService = saveService
        self.configurationProvider = configurationProvider
    }

    var isPresentingModalSheet: Bool {
        editorPanel?.attachedSheet != nil
    }

    func present(_ result: CaptureResult, visibleFrame: CGRect) {
        dismiss()
        let document = AnnotationDocument(sourceImage: result.image)
        let editor = AnnotationEditorView(
            document: document,
            onCopy: { [weak self] in
                guard let self else { return "Editor is no longer available" }
                do {
                    try clipboardService.write(exportedResult(document, source: result))
                    return "Copied annotated image"
                } catch {
                    return error.localizedDescription
                }
            },
            onSave: { [weak self] in
                guard let self else { return "Editor is no longer available" }
                do {
                    let outcome = try await saveService.saveAs(
                        exportedResult(document, source: result),
                        configuration: configurationProvider(),
                        presentingWindow: editorPanel
                    )
                    return switch outcome {
                    case let .saved(url): "Saved as \(url.lastPathComponent)"
                    case .discarded: "Save cancelled"
                    case let .failed(message): message
                    case .skipped: "Save skipped"
                    }
                } catch {
                    return error.localizedDescription
                }
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
        panel.title = "CapDeck Annotate"
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: editor)
        panel.minSize = NSSize(width: 780, height: 560)

        let panelSize = NSSize(
            width: min(1180, max(820, visibleFrame.width * 0.82)),
            height: min(820, max(600, visibleFrame.height * 0.82))
        )
        panel.setContentSize(panelSize)
        panel.setFrameOrigin(
            CGPoint(
                x: visibleFrame.midX - panel.frame.width / 2,
                y: visibleFrame.midY - panel.frame.height / 2
            )
        )
        editorPanel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        let closingPanel = editorPanel
        editorPanel = nil
        safelyClose(closingPanel)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let panel = sender as? NSPanel, panel === editorPanel else {
            return true
        }
        editorPanel = nil
        safelyClose(panel)
        return false
    }

    private func exportedResult(
        _ document: AnnotationDocument,
        source: CaptureResult
    ) throws -> CaptureResult {
        try CaptureResult(
            image: document.renderedImage(),
            displayID: source.displayID,
            timestamp: source.timestamp
        )
    }

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
}

private enum AnnotationTool: String, CaseIterable, Identifiable {
    case rectangle
    case arrow
    case text
    case blur
    case crop

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .rectangle: "Rectangle"
        case .arrow: "Arrow"
        case .text: "Text"
        case .blur: "Blur"
        case .crop: "Crop"
        }
    }

    var icon: String {
        switch self {
        case .rectangle: "rectangle"
        case .arrow: "arrow.up.right"
        case .text: "textformat"
        case .blur: "drop.halffull"
        case .crop: "crop"
        }
    }

    var instruction: String {
        switch self {
        case .rectangle: "Drag to draw a rectangle"
        case .arrow: "Drag from the arrow tail to its point"
        case .text: "Enter text, then drag its text box"
        case .blur: "Drag over information to obscure"
        case .crop: "Drag the output crop boundary"
        }
    }
}

@MainActor
private struct AnnotationEditorView: View {
    @ObservedObject var document: AnnotationDocument
    let onCopy: () -> String
    let onSave: () async -> String
    let onClose: () -> Void

    @State private var selectedTool: AnnotationTool = .rectangle
    @State private var selectedElementID: UUID?
    @State private var dragStart: CGPoint?
    @State private var draftEnd: CGPoint?
    @State private var textDraft = "Label"
    @State private var statusText = AnnotationTool.rectangle.instruction
    @State private var isSaving = false

    private var imageSize: CGSize {
        CGSize(width: document.sourceImage.width, height: document.sourceImage.height)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            annotationCanvas
            Divider()
            footer
        }
        .background(.background)
        .onChange(of: selectedTool) { _, tool in
            statusText = tool.instruction
        }
    }

    private var toolbar: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Picker("Tool", selection: $selectedTool) {
                    ForEach(AnnotationTool.allCases) { tool in
                        Label(tool.title, systemImage: tool.icon).tag(tool)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 530)

                Divider().frame(height: 24)

                Button {
                    document.undo()
                    selectedElementID = nil
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!document.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .accessibilityLabel("Undo annotation")
                .accessibilityIdentifier("annotation.undo")

                Button {
                    document.redo()
                    selectedElementID = nil
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!document.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .accessibilityLabel("Redo annotation")
                .accessibilityIdentifier("annotation.redo")

                Spacer()

                Text(outputSizeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if selectedTool == .text || selectedText != nil {
                    TextField("Text label", text: $textDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180, maxWidth: 320)
                        .onSubmit(updateSelectedText)

                    if selectedText != nil {
                        Button("Update Text", action: updateSelectedText)
                    }
                }

                Menu {
                    ForEach(Array(document.elements.enumerated()), id: \.element.id) {
                        index, element in
                        Button("\(index + 1). \(elementName(element))") {
                            select(element)
                        }
                    }
                } label: {
                    Label(
                        selectedElementID == nil ? "Elements" : "Element Selected",
                        systemImage: "square.stack.3d.up"
                    )
                }
                .disabled(document.elements.isEmpty)
                .accessibilityLabel("Annotation elements")
                .accessibilityIdentifier("annotation.elements")

                Button(role: .destructive) {
                    deleteSelectedElement()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedElementID == nil)
                .keyboardShortcut(.delete, modifiers: [])
                .accessibilityLabel("Delete selected annotation")
                .accessibilityIdentifier("annotation.delete")

                if document.cropRect != nil {
                    Button("Clear Crop") {
                        document.clearCrop()
                        statusText = "Crop cleared"
                    }
                }

                Spacer()
            }
        }
        .padding(12)
    }

    private var annotationCanvas: some View {
        GeometryReader { proxy in
            let localFittedRect = AnnotationCanvasGeometry.fittedRect(
                imageSize: imageSize,
                canvasSize: CGSize(
                    width: max(1, proxy.size.width - 32),
                    height: max(1, proxy.size.height - 32)
                )
            )
            let fittedRect = localFittedRect.offsetBy(dx: 16, dy: 16)

            ZStack(alignment: .topLeading) {
                Color(nsColor: .underPageBackgroundColor)

                Image(decorative: document.sourceImage, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: fittedRect.width, height: fittedRect.height)
                    .position(x: fittedRect.midX, y: fittedRect.midY)

                ForEach(document.elements) { element in
                    annotationOverlay(element, fittedRect: fittedRect)
                }

                cropOverlay(fittedRect: fittedRect)
                draftOverlay(fittedRect: fittedRect)
            }
            .contentShape(Rectangle())
            .gesture(toolGesture(fittedRect: fittedRect))
            .accessibilityLabel("Annotation canvas")
            .accessibilityHint(selectedTool.instruction)
        }
    }

    @ViewBuilder
    private func annotationOverlay(
        _ element: AnnotationElement,
        fittedRect: CGRect
    ) -> some View {
        switch element {
        case let .rectangle(annotation):
            let rect = canvasRect(annotation.rect, fittedRect: fittedRect)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .stroke(
                        annotationColor(annotation.color),
                        lineWidth: displayLineWidth(
                            annotation.lineWidth,
                            fittedRect: fittedRect
                        )
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                selectionBorder(for: element, rect: rect)
            }

        case let .arrow(annotation):
            let start = canvasPoint(annotation.start, fittedRect: fittedRect)
            let end = canvasPoint(annotation.end, fittedRect: fittedRect)
            arrowPath(from: start, to: end)
                .stroke(
                    annotationColor(annotation.color),
                    style: StrokeStyle(
                        lineWidth: displayLineWidth(annotation.lineWidth, fittedRect: fittedRect),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            if selectedElementID == element.id {
                let rect = selectionRect(for: element, fittedRect: fittedRect)
                selectionRectangle(rect)
            }

        case let .text(annotation):
            let rect = canvasRect(annotation.rect, fittedRect: fittedRect)
            ZStack(alignment: .topLeading) {
                Text(annotation.text)
                    .font(
                        .system(
                            size: max(
                                10,
                                annotation.fontSize / imageSize.width * fittedRect.width
                            ), weight: .bold
                        )
                    )
                    .foregroundStyle(annotationColor(annotation.color))
                    .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                    .position(x: rect.midX, y: rect.midY)
                selectionBorder(for: element, rect: rect)
            }

        case let .blur(annotation):
            let rect = canvasRect(annotation.rect, fittedRect: fittedRect)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.regularMaterial)
                    .overlay {
                        Label("Blur", systemImage: "drop.halffull")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                selectionBorder(for: element, rect: rect)
            }
        }
    }

    @ViewBuilder
    private func cropOverlay(fittedRect: CGRect) -> some View {
        if let cropRect = document.cropRect {
            let rect = canvasRect(cropRect, fittedRect: fittedRect)
            Path { path in
                path.addRect(fittedRect)
                path.addRect(rect)
            }
            .fill(.black.opacity(0.42), style: FillStyle(eoFill: true))

            Rectangle()
                .stroke(
                    .orange,
                    style: StrokeStyle(lineWidth: 2, dash: [7, 4])
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    @ViewBuilder
    private func draftOverlay(fittedRect _: CGRect) -> some View {
        if let start = dragStart, let end = draftEnd {
            if selectedTool == .arrow {
                arrowPath(from: start, to: end)
                    .stroke(
                        .red,
                        style: StrokeStyle(
                            lineWidth: 2,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: [6, 4]
                        )
                    )
            } else {
                let rect = normalizedRect(from: start, to: end)
                Rectangle()
                    .stroke(
                        selectedTool == .crop ? .orange : .red,
                        style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private func toolGesture(fittedRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard dragStart != nil || fittedRect.contains(value.startLocation) else {
                    return
                }
                if dragStart == nil {
                    dragStart = value.startLocation
                }
                draftEnd = clamped(value.location, to: fittedRect)
            }
            .onEnded { value in
                defer {
                    dragStart = nil
                    draftEnd = nil
                }
                guard let start = dragStart else { return }
                let imageStart = AnnotationCanvasGeometry.imagePoint(
                    from: start,
                    fittedRect: fittedRect,
                    imageSize: imageSize
                )
                let imageEnd = AnnotationCanvasGeometry.imagePoint(
                    from: value.location,
                    fittedRect: fittedRect,
                    imageSize: imageSize
                )
                applyTool(from: imageStart, to: imageEnd)
            }
    }

    private func applyTool(from start: CGPoint, to end: CGPoint) {
        let rect = normalizedRect(from: start, to: end)
        selectedElementID = nil
        switch selectedTool {
        case .rectangle:
            if document.addRectangle(rect) {
                statusText = "Rectangle added"
            }
        case .arrow:
            if document.addArrow(from: start, to: end) {
                statusText = "Arrow added"
            }
        case .text:
            let resolvedRect = textRect(from: rect, anchor: start)
            if let id = document.addText(textDraft, in: resolvedRect) {
                selectedElementID = id
                statusText = "Text added"
            } else {
                statusText = "Enter text before adding a label"
            }
        case .blur:
            if document.addBlur(rect) {
                statusText = "Blur region added"
            }
        case .crop:
            if document.setCrop(rect) {
                statusText = "Crop updated"
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()

            Button {
                Task {
                    isSaving = true
                    statusText = await onSave()
                    isSaving = false
                }
            } label: {
                if isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Save Annotated…", systemImage: "square.and.arrow.down")
                }
            }
            .disabled(isSaving)
            .accessibilityLabel("Save annotated image")
            .accessibilityIdentifier("annotation.save")

            Button {
                statusText = onCopy()
            } label: {
                Label("Copy Annotated", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .accessibilityLabel("Copy annotated image")
            .accessibilityIdentifier("annotation.copy")

            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("annotation.close")
        }
        .padding(12)
    }

    private var selectedText: TextAnnotation? {
        guard
            let element = document.element(id: selectedElementID),
            case let .text(annotation) = element
        else { return nil }
        return annotation
    }

    private var outputSizeText: String {
        "Output \(Int(document.outputPixelSize.width)) × \(Int(document.outputPixelSize.height)) px"
    }

    private func select(_ element: AnnotationElement) {
        selectedElementID = element.id
        if case let .text(annotation) = element {
            textDraft = annotation.text
            selectedTool = .text
        }
        statusText = "\(elementName(element)) selected"
    }

    private func updateSelectedText() {
        guard let id = selectedElementID else { return }
        if document.updateText(id: id, text: textDraft) {
            statusText = "Text updated"
        }
    }

    private func deleteSelectedElement() {
        guard let id = selectedElementID else { return }
        if document.deleteElement(id: id) {
            selectedElementID = nil
            statusText = "Element deleted"
        }
    }

    private func elementName(_ element: AnnotationElement) -> String {
        switch element {
        case .rectangle: "Rectangle"
        case .arrow: "Arrow"
        case let .text(annotation): "Text: \(annotation.text.prefix(18))"
        case .blur: "Blur"
        }
    }

    private func canvasRect(_ rect: CGRect, fittedRect: CGRect) -> CGRect {
        AnnotationCanvasGeometry.canvasRect(
            from: rect,
            fittedRect: fittedRect,
            imageSize: imageSize
        )
    }

    private func canvasPoint(_ point: CGPoint, fittedRect: CGRect) -> CGPoint {
        AnnotationCanvasGeometry.canvasPoint(
            from: point,
            fittedRect: fittedRect,
            imageSize: imageSize
        )
    }

    private func selectionRect(
        for element: AnnotationElement,
        fittedRect: CGRect
    ) -> CGRect {
        canvasRect(element.imageBounds, fittedRect: fittedRect)
            .insetBy(dx: -6, dy: -6)
    }

    @ViewBuilder
    private func selectionBorder(for element: AnnotationElement, rect: CGRect) -> some View {
        if selectedElementID == element.id {
            selectionRectangle(rect.insetBy(dx: -6, dy: -6))
        }
    }

    private func selectionRectangle(_ rect: CGRect) -> some View {
        Rectangle()
            .stroke(.yellow, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            .frame(width: max(12, rect.width), height: max(12, rect.height))
            .position(x: rect.midX, y: rect.midY)
    }

    private func annotationColor(_ color: AnnotationRGBA) -> Color {
        Color(
            red: color.red,
            green: color.green,
            blue: color.blue,
            opacity: color.alpha
        )
    }

    private func displayLineWidth(_ width: CGFloat, fittedRect: CGRect) -> CGFloat {
        max(2, width / imageSize.width * fittedRect.width)
    }

    private func arrowPath(from start: CGPoint, to end: CGPoint) -> Path {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let angle = atan2(dy, dx)
        let distance = max(1, hypot(dx, dy))
        let headLength = min(distance * 0.35, 18)
        let wing = CGFloat.pi / 6
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        path.move(to: end)
        path.addLine(
            to: CGPoint(
                x: end.x - headLength * cos(angle - wing),
                y: end.y - headLength * sin(angle - wing)
            )
        )
        path.move(to: end)
        path.addLine(
            to: CGPoint(
                x: end.x - headLength * cos(angle + wing),
                y: end.y - headLength * sin(angle + wing)
            )
        )
        return path
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func clamped(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func textRect(from draggedRect: CGRect, anchor: CGPoint) -> CGRect {
        if draggedRect.width >= 10, draggedRect.height >= 10 {
            return draggedRect
        }
        let fontSize = max(18, min(imageSize.width, imageSize.height) * 0.035)
        return CGRect(
            x: anchor.x,
            y: anchor.y,
            width: min(imageSize.width * 0.45, max(180, CGFloat(textDraft.count) * fontSize * 0.7)),
            height: fontSize * 2.6
        )
    }
}
