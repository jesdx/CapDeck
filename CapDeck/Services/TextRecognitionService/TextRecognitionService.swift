import CoreGraphics
import Foundation
import Vision

enum TextRecognitionServiceError: LocalizedError {
    case recognitionFailed

    var errorDescription: String? {
        "Text could not be recognized in this capture."
    }
}

/// Recognizes text in a capture. The Vision framework types stay behind this
/// boundary, and recognition runs off the main actor because it is CPU-heavy
/// image processing.
protocol TextRecognizing: Sendable {
    func recognizeText(in result: CaptureResult) async throws -> RecognizedText
}

/// Apple Vision implementation. Fully on-device: no network, no data leaves the
/// machine, so it keeps CapDeck's local-first, sandbox-friendly posture.
///
/// `nonisolated` so recognition runs on its background queue and not the main
/// actor. Without this, the project's default MainActor isolation would make
/// the Vision work trap the executor assertion when it runs off the main actor.
final nonisolated class VisionTextRecognitionService: TextRecognizing {
    private let queue = DispatchQueue(
        label: "com.jesdx.capdeck.text-recognition",
        qos: .userInitiated
    )

    func recognizeText(in result: CaptureResult) async throws -> RecognizedText {
        try Task.checkCancellation()
        let recognized: RecognizedText = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try continuation.resume(returning: Self.performRecognition(on: result.image))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        try Task.checkCancellation()
        return recognized
    }

    private static func performRecognition(on image: CGImage) throws -> RecognizedText {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw TextRecognitionServiceError.recognitionFailed
        }

        let observations = request.results ?? []
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        let lines: [RecognizedTextLine] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            // Vision boxes are normalized with a bottom-left origin; convert to
            // top-left pixel coordinates so later slices can crop against them.
            let box = observation.boundingBox
            let pixelBox = CGRect(
                x: box.minX * width,
                y: (1 - box.maxY) * height,
                width: box.width * width,
                height: box.height * height
            )
            return RecognizedTextLine(
                text: candidate.string,
                boundingBox: pixelBox,
                confidence: candidate.confidence
            )
        }

        let ordered = lines.sorted { lhs, rhs in
            if abs(lhs.boundingBox.minY - rhs.boundingBox.minY) > 1 {
                return lhs.boundingBox.minY < rhs.boundingBox.minY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        return RecognizedText(lines: ordered)
    }
}
