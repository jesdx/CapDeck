import AppKit
@testable import CapDeck
import CoreGraphics
import Foundation
import Testing

@MainActor
struct CaptureTextCopierTests {
    @Test
    func copiesRecognizedTextToTheClipboard() async throws {
        let recognizer = TextRecognizerFake(
            result: RecognizedText(lines: [
                line("Hello", y: 0),
                line("World", y: 40),
            ])
        )
        let clipboard = TextClipboardFake()
        let copier = CaptureTextCopier(recognizer: recognizer, clipboardService: clipboard)

        let outcome = try await copier.copyText(from: makeResult())

        #expect(outcome == .copied("Hello\nWorld"))
        #expect(clipboard.writtenText == ["Hello\nWorld"])
    }

    @Test
    func reportsNoTextFoundWithoutTouchingTheClipboard() async throws {
        let recognizer = TextRecognizerFake(result: .empty)
        let clipboard = TextClipboardFake()
        let copier = CaptureTextCopier(recognizer: recognizer, clipboardService: clipboard)

        let outcome = try await copier.copyText(from: makeResult())

        #expect(outcome == .noTextFound)
        #expect(clipboard.writtenText.isEmpty)
    }

    @Test
    func reportsCancellationSeparatelyFromFailure() async throws {
        let recognizer = TextRecognizerFake(error: CancellationError())
        let clipboard = TextClipboardFake()
        let copier = CaptureTextCopier(recognizer: recognizer, clipboardService: clipboard)

        let outcome = try await copier.copyText(from: makeResult())

        #expect(outcome == .cancelled)
        #expect(clipboard.writtenText.isEmpty)
    }

    @Test
    func recognitionFailureIsDistinguishedFromClipboardFailure() async throws {
        let recognizer = TextRecognizerFake(error: TextRecognitionServiceError.recognitionFailed)
        let clipboard = TextClipboardFake()
        let copier = CaptureTextCopier(recognizer: recognizer, clipboardService: clipboard)

        let outcome = try await copier.copyText(from: makeResult())

        #expect(outcome == .recognitionFailed)
        #expect(clipboard.writtenText.isEmpty)
    }

    @Test
    func clipboardFailureAfterSuccessfulRecognitionMapsToClipboardFailed() async throws {
        let recognizer = TextRecognizerFake(
            result: RecognizedText(lines: [line("Text", y: 0)])
        )
        let clipboard = TextClipboardFake(error: ClipboardServiceError.textWriteFailed)
        let copier = CaptureTextCopier(recognizer: recognizer, clipboardService: clipboard)

        let outcome = try await copier.copyText(from: makeResult())

        #expect(outcome == .clipboardFailed)
    }

    @Test
    func statusMessagesReadClearlyAndCancellationStaysSilent() {
        #expect(CopyTextOutcome.copied("hi").statusMessage == "Text copied")
        #expect(CopyTextOutcome.noTextFound.statusMessage == "No text found")
        #expect(CopyTextOutcome.recognitionFailed.statusMessage == "Text recognition failed")
        #expect(CopyTextOutcome.clipboardFailed.statusMessage == "Copy failed")
        #expect(CopyTextOutcome.cancelled.statusMessage == nil)
    }

    private func line(_ text: String, y: CGFloat) -> RecognizedTextLine {
        RecognizedTextLine(
            text: text,
            boundingBox: CGRect(x: 0, y: y, width: 100, height: 30),
            confidence: 1
        )
    }

    private func makeResult() throws -> CaptureResult {
        let context = try #require(
            CGContext(
                data: nil,
                width: 4,
                height: 4,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        return try CaptureResult(
            image: #require(context.makeImage()),
            displayID: 1,
            timestamp: Date()
        )
    }
}

private struct TextRecognizerFake: TextRecognizing {
    var result: RecognizedText = .empty
    var error: Error?

    func recognizeText(in _: CaptureResult) async throws -> RecognizedText {
        if let error {
            throw error
        }
        return result
    }
}

@MainActor
private final class TextClipboardFake: ClipboardWriting {
    private(set) var writtenText: [String] = []
    let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func write(_: CaptureResult) throws {}

    func writeText(_ text: String) throws {
        if let error {
            throw error
        }
        writtenText.append(text)
    }
}
