import Combine
import CoreGraphics
import Foundation

struct CaptureHistoryEntry: Identifiable {
    let id: UUID
    let result: CaptureResult
    let savedURL: URL?

    init(
        id: UUID = UUID(),
        result: CaptureResult,
        savedURL: URL? = nil
    ) {
        self.id = id
        self.result = result
        self.savedURL = savedURL
    }

    var estimatedPixelBytes: Int {
        result.image.bytesPerRow * result.image.height
    }
}

@MainActor
protocol CaptureHistoryRecording: AnyObject {
    func record(_ result: CaptureResult, saveOutcome: CaptureSaveOutcome)
}

@MainActor
final class CaptureHistoryStore: ObservableObject, CaptureHistoryRecording {
    static let defaultMaximumCount = 10
    static let defaultMaximumPixelBytes = 256 * 1_024 * 1_024

    @Published private(set) var entries: [CaptureHistoryEntry] = []

    let maximumCount: Int
    let maximumPixelBytes: Int

    init(
        maximumCount: Int = defaultMaximumCount,
        maximumPixelBytes: Int = defaultMaximumPixelBytes
    ) {
        self.maximumCount = max(1, maximumCount)
        self.maximumPixelBytes = max(1, maximumPixelBytes)
    }

    var estimatedPixelBytes: Int {
        entries.reduce(0) { $0 + $1.estimatedPixelBytes }
    }

    func record(_ result: CaptureResult, saveOutcome: CaptureSaveOutcome) {
        let savedURL: URL?
        if case let .saved(url) = saveOutcome {
            savedURL = url
        } else {
            savedURL = nil
        }

        entries.insert(
            CaptureHistoryEntry(result: result, savedURL: savedURL),
            at: 0
        )
        trimToLimits()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    func clear() {
        entries.removeAll(keepingCapacity: false)
    }

    private func trimToLimits() {
        if entries.count > maximumCount {
            entries.removeLast(entries.count - maximumCount)
        }

        // Keep the newest capture even when a single unusually large image is
        // over budget, then evict older images until the store is bounded.
        while entries.count > 1 && estimatedPixelBytes > maximumPixelBytes {
            entries.removeLast()
        }
    }
}
