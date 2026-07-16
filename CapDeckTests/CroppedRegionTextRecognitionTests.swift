import AppKit
@testable import CapDeck
import CoreGraphics
import CoreText
import Foundation
import Testing

/// Slice 2's promise: recognizing text in the Annotation editor reads the
/// rendered/cropped image, so a crop set around one region copies only that
/// region's text. Exercises AnnotationDocument + AnnotationRenderer + Vision
/// together on a real image.
@MainActor
struct CroppedRegionTextRecognitionTests {
    @Test
    func fullImageRecognizesTextFromBothRegions() async throws {
        let image = try makeTwoRegionImage()
        let recognized = try await VisionTextRecognitionService().recognizeText(
            in: CaptureResult(image: image, displayID: 1, timestamp: Date())
        )

        let text = recognized.joinedText.lowercased()
        #expect(text.contains("alpha"))
        #expect(text.contains("omega"))
    }

    @Test
    func cropRestrictsRecognitionToTheCroppedRegion() async throws {
        let document = try AnnotationDocument(sourceImage: makeTwoRegionImage())
        // Bottom half in top-left image coordinates (where "OMEGA" was drawn).
        #expect(document.setCrop(CGRect(x: 0, y: 200, width: 400, height: 200)))
        let rendered = try document.renderedImage()

        let recognized = try await VisionTextRecognitionService().recognizeText(
            in: CaptureResult(image: rendered, displayID: 1, timestamp: Date())
        )

        let text = recognized.joinedText.lowercased()
        #expect(text.contains("omega"))
        #expect(!text.contains("alpha"))
    }

    /// 400×400 white image with "ALPHA" in the top half and "OMEGA" in the
    /// bottom half. Text is drawn in Core Graphics' bottom-left space, so a high
    /// y is visually near the top.
    private func makeTwoRegionImage() throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil,
                width: 400,
                height: 400,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        draw("ALPHA", into: context, atBaselineY: 300)
        draw("OMEGA", into: context, atBaselineY: 70)
        return try #require(context.makeImage())
    }

    private func draw(_ text: String, into context: CGContext, atBaselineY y: CGFloat) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 72, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.black.cgColor,
            ]
        )
        let ctLine = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 40, y: y)
        CTLineDraw(ctLine, context)
    }
}
