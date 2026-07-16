import AppKit
@testable import CapDeck
import CoreGraphics
import Testing

@MainActor
struct AnnotationDocumentTests {
    @Test
    func rectangleIsClippedToSourceBounds() throws {
        let document = try AnnotationDocument(sourceImage: makeWhiteImage(width: 20, height: 10))

        let added = document.addRectangle(
            CGRect(x: -5, y: -2, width: 16, height: 8),
            lineWidth: 2
        )

        #expect(added)
        #expect(document.elements.count == 1)
        guard case let .rectangle(annotation) = document.elements[0] else {
            Issue.record("Expected a rectangle annotation")
            return
        }
        #expect(annotation.rect == CGRect(x: 0, y: 0, width: 11, height: 6))
    }

    @Test
    func undoRedoAndNewEditMaintainCommandHistory() throws {
        let document = try AnnotationDocument(sourceImage: makeWhiteImage(width: 40, height: 30))
        document.addRectangle(CGRect(x: 2, y: 2, width: 10, height: 8))
        document.addRectangle(CGRect(x: 15, y: 10, width: 12, height: 9))

        document.undo()
        #expect(document.elements.count == 1)
        #expect(document.canRedo)

        document.redo()
        #expect(document.elements.count == 2)
        #expect(!document.canRedo)

        document.undo()
        document.addRectangle(CGRect(x: 5, y: 15, width: 8, height: 8))
        #expect(document.elements.count == 2)
        #expect(!document.canRedo)
    }

    @Test
    func renderingKeepsDimensionsAndDrawsWithoutMutatingSource() throws {
        let source = try makeWhiteImage(width: 24, height: 18)
        let document = AnnotationDocument(sourceImage: source)
        document.addRectangle(
            CGRect(x: 2, y: 2, width: 18, height: 12),
            lineWidth: 3
        )

        let rendered = try document.renderedImage()

        #expect(rendered.width == source.width)
        #expect(rendered.height == source.height)
        #expect(redPixelCount(in: source) == 0)
        #expect(redPixelCount(in: rendered) > 0)
    }

    @Test
    func arrowAndTextRenderWithoutChangingSourceDimensions() throws {
        let source = try makeWhiteImage(width: 160, height: 100)
        let document = AnnotationDocument(sourceImage: source)

        #expect(document.addArrow(from: CGPoint(x: 12, y: 82), to: CGPoint(x: 110, y: 20)))
        let textID = document.addText(
            "CapDeck",
            in: CGRect(x: 20, y: 15, width: 120, height: 38),
            fontSize: 24
        )
        #expect(textID != nil)

        let rendered = try document.renderedImage()

        #expect(rendered.width == 160)
        #expect(rendered.height == 100)
        #expect(redPixelCount(in: rendered) > 40)
        #expect(redPixelCount(in: source) == 0)
    }

    @Test
    func textCanBeEditedDeletedAndRestored() throws {
        let document = try AnnotationDocument(sourceImage: makeWhiteImage(width: 120, height: 80))
        let textID = try #require(
            document.addText("Before", in: CGRect(x: 10, y: 10, width: 90, height: 30))
        )

        #expect(document.updateText(id: textID, text: "After"))
        guard case let .text(updated) = document.elements.first else {
            Issue.record("Expected a text annotation")
            return
        }
        #expect(updated.text == "After")

        #expect(document.deleteElement(id: textID))
        #expect(document.elements.isEmpty)
        document.undo()
        #expect(document.elements.count == 1)
        document.undo()
        guard case let .text(original) = document.elements.first else {
            Issue.record("Expected restored text")
            return
        }
        #expect(original.text == "Before")
        document.redo()
        guard case let .text(redone) = document.elements.first else {
            Issue.record("Expected redone text")
            return
        }
        #expect(redone.text == "After")
    }

    @Test
    func blurChangesOnlyTheSelectedRegion() throws {
        let source = try makeSplitImage(width: 80, height: 40)
        let document = AnnotationDocument(sourceImage: source)
        #expect(document.addBlur(CGRect(x: 32, y: 0, width: 16, height: 40), radius: 8))

        let rendered = try document.renderedImage()

        #expect(rendered.width == source.width)
        #expect(rendered.height == source.height)
        #expect(pixel(in: rendered, x: 5, y: 20) == pixel(in: source, x: 5, y: 20))
        #expect(pixel(in: rendered, x: 38, y: 20) != pixel(in: source, x: 38, y: 20))
    }

    @Test
    func cropUsesTopLeftImageCoordinatesAndParticipatesInUndoRedo() throws {
        let source = try makeQuadrantImage(width: 100, height: 80)
        let document = AnnotationDocument(sourceImage: source)

        #expect(document.setCrop(CGRect(x: 50, y: 0, width: 50, height: 40)))
        #expect(document.outputPixelSize == CGSize(width: 50, height: 40))
        let cropped = try document.renderedImage()

        #expect(cropped.width == 50)
        #expect(cropped.height == 40)
        #expect(isMostlyGreen(pixel(in: cropped, x: 25, y: 20)))

        document.undo()
        #expect(document.cropRect == nil)
        #expect(document.outputPixelSize == CGSize(width: 100, height: 80))
        document.redo()
        #expect(document.cropRect == CGRect(x: 50, y: 0, width: 50, height: 40))
    }

    @Test
    func canvasGeometryFitsAndMapsRetinaSizedImages() {
        let fitted = AnnotationCanvasGeometry.fittedRect(
            imageSize: CGSize(width: 3024, height: 1964),
            canvasSize: CGSize(width: 900, height: 700)
        )
        let center = AnnotationCanvasGeometry.imagePoint(
            from: CGPoint(x: fitted.midX, y: fitted.midY),
            fittedRect: fitted,
            imageSize: CGSize(width: 3024, height: 1964)
        )

        #expect(fitted.width == 900)
        #expect(abs(center.x - 1512) < 0.001)
        #expect(abs(center.y - 982) < 0.001)
    }

    @Test
    func canvasPointMappingClampsOutsideTheImage() {
        let fitted = CGRect(x: 50, y: 25, width: 200, height: 100)

        let point = AnnotationCanvasGeometry.imagePoint(
            from: CGPoint(x: 500, y: -100),
            fittedRect: fitted,
            imageSize: CGSize(width: 1000, height: 500)
        )

        #expect(point == CGPoint(x: 1000, y: 0))
    }

    private func makeWhiteImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func makeSplitImage(width: Int, height: Int) throws -> CGImage {
        let context = try makeContext(width: width, height: height)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        return try #require(context.makeImage())
    }

    private func makeQuadrantImage(width: Int, height: Int) throws -> CGImage {
        let context = try makeContext(width: width, height: height)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: width / 2, y: height / 2, width: width / 2, height: height / 2))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height / 2))
        return try #require(context.makeImage())
    }

    private func makeContext(width: Int, height: Int) throws -> CGContext {
        try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
    }

    private func pixel(in image: CGImage, x: Int, y: Int) -> NSColor? {
        NSBitmapImageRep(cgImage: image)
            .colorAt(x: x, y: y)?
            .usingColorSpace(.deviceRGB)
    }

    private func isMostlyGreen(_ color: NSColor?) -> Bool {
        guard let color else { return false }
        return color.greenComponent > 0.8
            && color.redComponent < 0.2
            && color.blueComponent < 0.2
    }

    private func redPixelCount(in image: CGImage) -> Int {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var count = 0
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide {
                guard
                    let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                else { continue }
                if color.redComponent > 0.8,
                   color.greenComponent < 0.4,
                   color.blueComponent < 0.4
                {
                    count += 1
                }
            }
        }
        return count
    }
}
