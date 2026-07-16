import Foundation

/// Result of a "Copy Text" action, kept UI-free so the presentation layer maps
/// it to a user-facing message and callers can unit-test the workflow.
enum CopyTextOutcome: Equatable {
    case copied(String)
    case noTextFound
    case cancelled
    case failed
}

/// Orchestrates recognizing text in a capture and placing it on the clipboard.
/// Lives in the feature layer (workflow ordering), not in a service, and is
/// shared by Preview now and by History/Annotation in later slices.
@MainActor
final class CaptureTextCopier {
    private let recognizer: TextRecognizing
    private let clipboardService: ClipboardWriting

    init(recognizer: TextRecognizing, clipboardService: ClipboardWriting) {
        self.recognizer = recognizer
        self.clipboardService = clipboardService
    }

    func copyText(from result: CaptureResult) async -> CopyTextOutcome {
        let recognized: RecognizedText
        do {
            recognized = try await recognizer.recognizeText(in: result)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed
        }

        let text = recognized.joinedText
        guard !text.isEmpty else { return .noTextFound }

        do {
            try clipboardService.writeText(text)
            return .copied(text)
        } catch {
            return .failed
        }
    }
}
