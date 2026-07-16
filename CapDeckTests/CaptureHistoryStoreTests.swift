@testable import CapDeck
import CoreGraphics
import Foundation
import Testing

@MainActor
struct CaptureHistoryStoreTests {
    @Test
    func retainsNewestEntriesWithinTheCountLimit() throws {
        let store = CaptureHistoryStore(maximumCount: 3, maximumPixelBytes: .max)

        for second in 0 ..< 5 {
            try store.record(
                makeResult(width: 2, height: 2, timestamp: Date(timeIntervalSince1970: Double(second))),
                saveOutcome: .skipped
            )
        }

        #expect(store.entries.count == 3)
        #expect(store.entries.map(\.result.timestamp.timeIntervalSince1970) == [4, 3, 2])
        #expect(store.entries.allSatisfy { $0.savedURL == nil })
    }

    @Test
    func memoryBudgetEvictsOlderImagesButKeepsNewestCapture() throws {
        let sample = try makeResult(width: 20, height: 20)
        let entryBytes = sample.image.bytesPerRow * sample.image.height
        let store = CaptureHistoryStore(
            maximumCount: 10,
            maximumPixelBytes: entryBytes * 2
        )

        store.record(sample, saveOutcome: .skipped)
        try store.record(makeResult(width: 20, height: 20), saveOutcome: .skipped)
        try store.record(makeResult(width: 20, height: 20), saveOutcome: .skipped)

        #expect(store.entries.count == 2)
        #expect(store.estimatedPixelBytes <= entryBytes * 2)
    }

    @Test
    func savedReferenceIsMetadataOnlyAndClearReleasesSessionHistory() throws {
        let store = CaptureHistoryStore()
        let url = URL(fileURLWithPath: "/tmp/user-selected/CapDeck.png")
        try store.record(makeResult(width: 4, height: 3), saveOutcome: .saved(url))

        #expect(store.entries.first?.savedURL == url)
        store.clear()
        #expect(store.entries.isEmpty)
        #expect(store.estimatedPixelBytes == 0)
    }

    private func makeResult(
        width: Int,
        height: Int,
        timestamp: Date = Date()
    ) throws -> CaptureResult {
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
        return try CaptureResult(
            image: #require(context.makeImage()),
            displayID: 1,
            timestamp: timestamp
        )
    }
}
