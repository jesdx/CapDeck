import AppKit
@testable import CapDeck
import CoreGraphics
import CoreText
import Foundation
import Testing

struct TextRecognitionServiceTests {
    @Test
    func recognizesRenderedTextFromTheCanonicalImage() async throws {
        let image = try makeTextImage("Hello", width: 320, height: 120)
        let service = VisionTextRecognitionService()

        let recognized = try await service.recognizeText(
            in: CaptureResult(image: image, displayID: 1, timestamp: Date())
        )

        #expect(!recognized.isEmpty)
        #expect(recognized.joinedText.lowercased().contains("hello"))
    }

    @Test
    func returnsEmptyResultForABlankImage() async throws {
        let image = try makeBlankImage(width: 200, height: 120)
        let service = VisionTextRecognitionService()

        let recognized = try await service.recognizeText(
            in: CaptureResult(image: image, displayID: 1, timestamp: Date())
        )

        #expect(recognized.isEmpty)
        #expect(recognized.lines.isEmpty)
    }

    @Test
    func cancellationBeforeRecognitionThrowsCancellationError() async throws {
        let image = try makeBlankImage(width: 40, height: 40)
        let service = VisionTextRecognitionService()
        let result = CaptureResult(image: image, displayID: 1, timestamp: Date())

        let task = Task {
            try await service.recognizeText(in: result)
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    private func makeBlankImage(width: Int, height: Int) throws -> CGImage {
        let context = try makeContext(width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func makeTextImage(_ text: String, width: Int, height: Int) throws -> CGImage {
        let context = try makeContext(width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica" as CFString, 56, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black.cgColor,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let ctLine = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 24, y: CGFloat(height) / 2 - 20)
        CTLineDraw(ctLine, context)

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
}
