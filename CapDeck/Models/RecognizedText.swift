import CoreGraphics
import Foundation

/// One recognized line of text and where it sits in the source capture, in
/// top-left pixel coordinates. Later slices use `boundingBox` to OCR only a
/// cropped region; slice 1 only reads `text`.
///
/// `nonisolated` because this is pure Sendable data that crosses actors: the
/// recognizer produces it off the main actor and callers read it anywhere.
nonisolated struct RecognizedTextLine: Equatable, Sendable {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
}

/// The full result of recognizing text in one capture: the individual lines in
/// reading order plus the joined plain-text string derived from them.
nonisolated struct RecognizedText: Equatable, Sendable {
    let lines: [RecognizedTextLine]

    static let empty = RecognizedText(lines: [])

    var isEmpty: Bool {
        joinedText.isEmpty
    }

    /// Lines joined top-to-bottom with newlines, matching how the text reads.
    var joinedText: String {
        lines
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
