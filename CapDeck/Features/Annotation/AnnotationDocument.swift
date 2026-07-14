import Combine
import CoreGraphics
import CoreImage
import CoreText
import Foundation

struct AnnotationRGBA: Equatable, Sendable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    static let red = AnnotationRGBA(red: 1, green: 0.12, blue: 0.08, alpha: 1)
    static let orange = AnnotationRGBA(red: 1, green: 0.48, blue: 0.08, alpha: 1)

    nonisolated var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

struct RectangleAnnotation: Equatable, Identifiable, Sendable {
    let id: UUID
    let rect: CGRect
    let color: AnnotationRGBA
    let lineWidth: CGFloat

    init(
        id: UUID = UUID(),
        rect: CGRect,
        color: AnnotationRGBA = .red,
        lineWidth: CGFloat
    ) {
        self.id = id
        self.rect = rect.standardized
        self.color = color
        self.lineWidth = lineWidth
    }
}

struct ArrowAnnotation: Equatable, Identifiable, Sendable {
    let id: UUID
    let start: CGPoint
    let end: CGPoint
    let color: AnnotationRGBA
    let lineWidth: CGFloat

    init(
        id: UUID = UUID(),
        start: CGPoint,
        end: CGPoint,
        color: AnnotationRGBA = .red,
        lineWidth: CGFloat
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.color = color
        self.lineWidth = lineWidth
    }
}

struct TextAnnotation: Equatable, Identifiable, Sendable {
    let id: UUID
    let rect: CGRect
    let text: String
    let color: AnnotationRGBA
    let fontSize: CGFloat

    init(
        id: UUID = UUID(),
        rect: CGRect,
        text: String,
        color: AnnotationRGBA = .red,
        fontSize: CGFloat
    ) {
        self.id = id
        self.rect = rect.standardized
        self.text = text
        self.color = color
        self.fontSize = fontSize
    }
}

struct BlurAnnotation: Equatable, Identifiable, Sendable {
    let id: UUID
    let rect: CGRect
    let radius: CGFloat

    init(id: UUID = UUID(), rect: CGRect, radius: CGFloat) {
        self.id = id
        self.rect = rect.standardized
        self.radius = radius
    }
}

enum AnnotationElement: Equatable, Identifiable, Sendable {
    case rectangle(RectangleAnnotation)
    case arrow(ArrowAnnotation)
    case text(TextAnnotation)
    case blur(BlurAnnotation)

    var id: UUID {
        switch self {
        case let .rectangle(annotation): annotation.id
        case let .arrow(annotation): annotation.id
        case let .text(annotation): annotation.id
        case let .blur(annotation): annotation.id
        }
    }

    var imageBounds: CGRect {
        switch self {
        case let .rectangle(annotation): annotation.rect
        case let .arrow(annotation):
            CGRect(
                x: min(annotation.start.x, annotation.end.x),
                y: min(annotation.start.y, annotation.end.y),
                width: abs(annotation.end.x - annotation.start.x),
                height: abs(annotation.end.y - annotation.start.y)
            )
        case let .text(annotation): annotation.rect
        case let .blur(annotation): annotation.rect
        }
    }
}

enum AnnotationRenderingError: LocalizedError {
    case contextCreationFailed
    case imageCreationFailed

    var errorDescription: String? {
        switch self {
        case .contextCreationFailed:
            "CapDeck could not create an annotation canvas."
        case .imageCreationFailed:
            "CapDeck could not render the annotated image."
        }
    }
}

private struct AnnotationSnapshot: Equatable {
    let elements: [AnnotationElement]
    let cropRect: CGRect?
}

@MainActor
final class AnnotationDocument: ObservableObject {
    let sourceImage: CGImage
    @Published private(set) var elements: [AnnotationElement] = []
    @Published private(set) var cropRect: CGRect?
    @Published private var undoStack: [AnnotationSnapshot] = []
    @Published private var redoStack: [AnnotationSnapshot] = []

    init(sourceImage: CGImage) {
        self.sourceImage = sourceImage
    }

    var imageBounds: CGRect {
        CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
    }

    var outputPixelSize: CGSize {
        cropRect?.integral.size ?? imageBounds.size
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func element(id: UUID?) -> AnnotationElement? {
        guard let id else { return nil }
        return elements.first { $0.id == id }
    }

    @discardableResult
    func addRectangle(
        _ rect: CGRect,
        color: AnnotationRGBA = .red,
        lineWidth: CGFloat? = nil
    ) -> Bool {
        guard let clipped = validRect(rect) else { return false }
        let resolvedLineWidth = lineWidth ?? defaultLineWidth
        commit {
            elements.append(
                .rectangle(
                    RectangleAnnotation(
                        rect: clipped,
                        color: color,
                        lineWidth: resolvedLineWidth
                    )
                )
            )
        }
        return true
    }

    @discardableResult
    func addArrow(
        from start: CGPoint,
        to end: CGPoint,
        color: AnnotationRGBA = .red,
        lineWidth: CGFloat? = nil
    ) -> Bool {
        let clippedStart = clippedPoint(start)
        let clippedEnd = clippedPoint(end)
        guard hypot(clippedEnd.x - clippedStart.x, clippedEnd.y - clippedStart.y) >= 3 else {
            return false
        }
        let resolvedLineWidth = lineWidth ?? defaultLineWidth
        commit {
            elements.append(
                .arrow(
                    ArrowAnnotation(
                        start: clippedStart,
                        end: clippedEnd,
                        color: color,
                        lineWidth: resolvedLineWidth
                    )
                )
            )
        }
        return true
    }

    @discardableResult
    func addText(
        _ text: String,
        in rect: CGRect,
        color: AnnotationRGBA = .red,
        fontSize: CGFloat? = nil
    ) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let clipped = validRect(rect) else { return nil }
        let annotation = TextAnnotation(
            rect: clipped,
            text: trimmed,
            color: color,
            fontSize: fontSize ?? max(18, min(imageBounds.width, imageBounds.height) * 0.035)
        )
        commit { elements.append(.text(annotation)) }
        return annotation.id
    }

    @discardableResult
    func updateText(id: UUID, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            let index = elements.firstIndex(where: { $0.id == id }),
            case let .text(annotation) = elements[index],
            annotation.text != trimmed
        else { return false }

        commit {
            elements[index] = .text(
                TextAnnotation(
                    id: annotation.id,
                    rect: annotation.rect,
                    text: trimmed,
                    color: annotation.color,
                    fontSize: annotation.fontSize
                )
            )
        }
        return true
    }

    @discardableResult
    func addBlur(_ rect: CGRect, radius: CGFloat? = nil) -> Bool {
        guard let clipped = validRect(rect) else { return false }
        let resolvedRadius =
            radius
            ?? max(12, min(imageBounds.width, imageBounds.height) * 0.018)
        commit {
            elements.append(.blur(BlurAnnotation(rect: clipped, radius: resolvedRadius)))
        }
        return true
    }

    @discardableResult
    func setCrop(_ rect: CGRect) -> Bool {
        guard let clipped = validRect(rect) else { return false }
        let pixelAligned = pixelAlignedRect(clipped)
        guard pixelAligned != cropRect else { return false }
        commit { cropRect = pixelAligned }
        return true
    }

    func clearCrop() {
        guard cropRect != nil else { return }
        commit { cropRect = nil }
    }

    @discardableResult
    func deleteElement(id: UUID) -> Bool {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return false }
        commit { elements.remove(at: index) }
        return true
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot)
        restore(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot)
        restore(snapshot)
    }

    func renderedImage() throws -> CGImage {
        try AnnotationRenderer.render(
            source: sourceImage,
            elements: elements,
            cropRect: cropRect
        )
    }

    private var defaultLineWidth: CGFloat {
        max(4, min(imageBounds.width, imageBounds.height) * 0.004)
    }

    private var currentSnapshot: AnnotationSnapshot {
        AnnotationSnapshot(elements: elements, cropRect: cropRect)
    }

    private func commit(_ mutation: () -> Void) {
        undoStack.append(currentSnapshot)
        redoStack.removeAll()
        mutation()
    }

    private func restore(_ snapshot: AnnotationSnapshot) {
        elements = snapshot.elements
        cropRect = snapshot.cropRect
    }

    private func validRect(_ rect: CGRect) -> CGRect? {
        let clipped = rect.standardized.intersection(imageBounds)
        guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else {
            return nil
        }
        return clipped
    }

    private func clippedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, imageBounds.minX), imageBounds.maxX),
            y: min(max(point.y, imageBounds.minY), imageBounds.maxY)
        )
    }

    private func pixelAlignedRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: floor(rect.minX),
            y: floor(rect.minY),
            width: ceil(rect.maxX) - floor(rect.minX),
            height: ceil(rect.maxY) - floor(rect.minY)
        ).intersection(imageBounds)
    }
}

enum AnnotationRenderer {
    nonisolated static func render(
        source: CGImage,
        elements: [AnnotationElement],
        cropRect: CGRect? = nil
    ) throws -> CGImage {
        let width = source.width
        let height = source.height
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let colorSpace =
            source.colorSpace
            ?? CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        guard let context = makeContext(width: width, height: height, colorSpace: colorSpace) else {
            throw AnnotationRenderingError.contextCreationFailed
        }

        context.draw(source, in: bounds)
        drawBlurRegions(
            elements.compactMap {
                guard case let .blur(annotation) = $0 else { return nil }
                return annotation
            },
            source: source,
            in: context,
            bounds: bounds
        )
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for element in elements {
            switch element {
            case let .rectangle(annotation):
                drawRectangle(annotation, in: context, imageHeight: CGFloat(height), bounds: bounds)
            case let .arrow(annotation):
                drawArrow(annotation, in: context, imageHeight: CGFloat(height))
            case let .text(annotation):
                drawText(annotation, in: context, imageHeight: CGFloat(height), bounds: bounds)
            case .blur:
                break
            }
        }

        guard let fullImage = context.makeImage() else {
            throw AnnotationRenderingError.imageCreationFailed
        }
        guard let cropRect else { return fullImage }
        return try crop(
            fullImage,
            topLeftRect: cropRect.intersection(bounds),
            colorSpace: colorSpace
        )
    }

    private nonisolated static func makeContext(
        width: Int,
        height: Int,
        colorSpace: CGColorSpace
    ) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private nonisolated static func drawBlurRegions(
        _ regions: [BlurAnnotation],
        source: CGImage,
        in context: CGContext,
        bounds: CGRect
    ) {
        guard !regions.isEmpty else { return }
        let input = CIImage(cgImage: source)
        let ciContext = CIContext(options: [.cacheIntermediates: false])

        for region in regions {
            let blurred =
                input
                .clampedToExtent()
                .applyingFilter(
                    "CIGaussianBlur",
                    parameters: [kCIInputRadiusKey: max(1, region.radius)]
                )
                .cropped(to: input.extent)
            guard let blurredImage = ciContext.createCGImage(blurred, from: input.extent) else {
                continue
            }
            let clipRect = coreGraphicsRect(
                from: region.rect.intersection(bounds),
                imageHeight: bounds.height
            )
            context.saveGState()
            context.clip(to: clipRect)
            context.draw(blurredImage, in: bounds)
            context.restoreGState()
        }
    }

    private nonisolated static func drawRectangle(
        _ annotation: RectangleAnnotation,
        in context: CGContext,
        imageHeight: CGFloat,
        bounds: CGRect
    ) {
        let lineWidth = max(1, annotation.lineWidth)
        let rect = coreGraphicsRect(
            from: annotation.rect.intersection(bounds),
            imageHeight: imageHeight
        ).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        guard rect.width > 0, rect.height > 0 else { return }
        context.setStrokeColor(annotation.color.cgColor)
        context.setLineWidth(lineWidth)
        context.stroke(rect)
    }

    private nonisolated static func drawArrow(
        _ annotation: ArrowAnnotation,
        in context: CGContext,
        imageHeight: CGFloat
    ) {
        let start = CGPoint(x: annotation.start.x, y: imageHeight - annotation.start.y)
        let end = CGPoint(x: annotation.end.x, y: imageHeight - annotation.end.y)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = max(1, hypot(dx, dy))
        let angle = atan2(dy, dx)
        let lineWidth = max(1, annotation.lineWidth)
        let headLength = min(distance * 0.35, max(lineWidth * 5, 14))
        let wingAngle = CGFloat.pi / 6

        context.setStrokeColor(annotation.color.cgColor)
        context.setLineWidth(lineWidth)
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.move(to: end)
        context.addLine(
            to: CGPoint(
                x: end.x - headLength * cos(angle - wingAngle),
                y: end.y - headLength * sin(angle - wingAngle)
            )
        )
        context.move(to: end)
        context.addLine(
            to: CGPoint(
                x: end.x - headLength * cos(angle + wingAngle),
                y: end.y - headLength * sin(angle + wingAngle)
            )
        )
        context.strokePath()
    }

    private nonisolated static func drawText(
        _ annotation: TextAnnotation,
        in context: CGContext,
        imageHeight: CGFloat,
        bounds: CGRect
    ) {
        let rect = coreGraphicsRect(
            from: annotation.rect.intersection(bounds),
            imageHeight: imageHeight
        )
        guard rect.width > 0, rect.height > 0 else { return }
        let font = CTFontCreateWithName(
            "Helvetica-Bold" as CFString,
            max(8, annotation.fontSize),
            nil
        )
        let attributed = NSAttributedString(
            string: annotation.text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    annotation.color.cgColor,
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            path,
            nil
        )
        context.saveGState()
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private nonisolated static func crop(
        _ image: CGImage,
        topLeftRect: CGRect,
        colorSpace: CGColorSpace
    ) throws -> CGImage {
        let rect = CGRect(
            x: floor(topLeftRect.minX),
            y: floor(topLeftRect.minY),
            width: ceil(topLeftRect.maxX) - floor(topLeftRect.minX),
            height: ceil(topLeftRect.maxY) - floor(topLeftRect.minY)
        )
        let outputWidth = max(1, Int(rect.width))
        let outputHeight = max(1, Int(rect.height))
        guard
            let context = makeContext(
                width: outputWidth,
                height: outputHeight,
                colorSpace: colorSpace
            )
        else {
            throw AnnotationRenderingError.contextCreationFailed
        }

        let sourceHeight = CGFloat(image.height)
        let lowerLeftY = sourceHeight - rect.maxY
        context.draw(
            image,
            in: CGRect(
                x: -rect.minX,
                y: -lowerLeftY,
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
        )
        guard let cropped = context.makeImage() else {
            throw AnnotationRenderingError.imageCreationFailed
        }
        return cropped
    }

    private nonisolated static func coreGraphicsRect(
        from topLeftRect: CGRect,
        imageHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: topLeftRect.minX,
            y: imageHeight - topLeftRect.maxY,
            width: topLeftRect.width,
            height: topLeftRect.height
        )
    }
}

enum AnnotationCanvasGeometry {
    nonisolated static func fittedRect(
        imageSize: CGSize,
        canvasSize: CGSize
    ) -> CGRect {
        guard
            imageSize.width > 0,
            imageSize.height > 0,
            canvasSize.width > 0,
            canvasSize.height > 0
        else { return .zero }

        let scale = min(
            canvasSize.width / imageSize.width,
            canvasSize.height / imageSize.height
        )
        let fittedSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return CGRect(
            x: (canvasSize.width - fittedSize.width) / 2,
            y: (canvasSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    nonisolated static func imagePoint(
        from canvasPoint: CGPoint,
        fittedRect: CGRect,
        imageSize: CGSize
    ) -> CGPoint {
        guard fittedRect.width > 0, fittedRect.height > 0 else { return .zero }
        let clampedX = min(max(canvasPoint.x, fittedRect.minX), fittedRect.maxX)
        let clampedY = min(max(canvasPoint.y, fittedRect.minY), fittedRect.maxY)
        return CGPoint(
            x: (clampedX - fittedRect.minX) / fittedRect.width * imageSize.width,
            y: (clampedY - fittedRect.minY) / fittedRect.height * imageSize.height
        )
    }

    nonisolated static func canvasPoint(
        from imagePoint: CGPoint,
        fittedRect: CGRect,
        imageSize: CGSize
    ) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        return CGPoint(
            x: fittedRect.minX + imagePoint.x / imageSize.width * fittedRect.width,
            y: fittedRect.minY + imagePoint.y / imageSize.height * fittedRect.height
        )
    }

    nonisolated static func canvasRect(
        from imageRect: CGRect,
        fittedRect: CGRect,
        imageSize: CGSize
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        return CGRect(
            x: fittedRect.minX + imageRect.minX / imageSize.width * fittedRect.width,
            y: fittedRect.minY + imageRect.minY / imageSize.height * fittedRect.height,
            width: imageRect.width / imageSize.width * fittedRect.width,
            height: imageRect.height / imageSize.height * fittedRect.height
        )
    }
}
