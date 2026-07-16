import AppKit
@testable import CapDeck
import CoreGraphics
import Foundation
import Testing

@MainActor
struct CaptureSavingTests {
    @Test
    func savePanelAttachesAboveItsPresentingWindow() async throws {
        let parent = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        parent.title = "Save Panel Test Parent"
        parent.makeKeyAndOrderFront(nil)
        defer {
            parent.orderOut(nil)
            parent.close()
        }

        let context = try #require(
            CGContext(
                data: nil,
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let result = try CaptureResult(
            image: #require(context.makeImage()),
            displayID: 1,
            timestamp: Date()
        )
        let service = CaptureFileService()
        let saveTask = Task {
            await service.saveAs(
                result,
                configuration: CaptureSaveConfiguration(
                    format: .png,
                    jpegQuality: 0.9,
                    filenamePattern: "CapDeck-Sheet-Test",
                    folderBookmark: nil
                ),
                presentingWindow: parent
            )
        }

        for _ in 0 ..< 100 where parent.attachedSheet == nil {
            try await Task.sleep(for: .milliseconds(20))
        }

        let savePanel = try #require(parent.attachedSheet as? NSSavePanel)
        #expect(savePanel.sheetParent === parent)
        savePanel.cancel(nil)
        #expect(await saveTask.value == .discarded)
    }

    @Test
    func filenamePatternRendersStableTokens() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = 2026
        components.month = 7
        components.day = 14
        components.hour = 9
        components.minute = 8
        components.second = 7
        let date = try #require(components.date)

        let filename = try FilenamePattern.render(
            "Capture-{date}-{time}-{timestamp}",
            date: date
        )

        #expect(filename == "Capture-2026-07-14-09-08-07-20260714-090807")
    }

    @Test
    func filenamePatternRejectsUnsafeCharactersAndUnknownTokens() {
        #expect(FilenamePattern.validate("folder/name") == .invalidCharacter("/"))
        #expect(FilenamePattern.validate("Capture-{screen}") == .unsupportedToken("screen"))
    }

    @Test
    func filenamePatternRejectsLeadingDotHiddenFiles() {
        #expect(FilenamePattern.validate(".hidden") == .leadingDot)
        #expect(FilenamePattern.validate("  .{date}") == .leadingDot)
        #expect(FilenamePattern.validate("CapDeck-{date}") == nil)
    }

    @Test
    func encodesPNGAndJPEGAtOriginalPixelDimensions() throws {
        let context = try #require(
            CGContext(
                data: nil,
                width: 7,
                height: 5,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let image = try #require(context.makeImage())

        for format in ImageFormat.allCases {
            let data = try CaptureImageEncoder.data(
                for: image,
                format: format,
                jpegQuality: 0.9
            )
            let representation = try #require(NSBitmapImageRep(data: data))
            #expect(representation.pixelsWide == 7)
            #expect(representation.pixelsHigh == 5)
        }
    }

    @Test
    func collisionSafeNameNeverSilentlyOverwrites() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapDeckTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let proposed = folder.appendingPathComponent("Capture.png")
        let second = folder.appendingPathComponent("Capture-2.png")
        try Data().write(to: proposed)
        try Data().write(to: second)

        let result = CollisionSafeFileURL.make(from: proposed)

        #expect(result.lastPathComponent == "Capture-3.png")
    }

    @Test
    func exclusiveWriterRejectsAnExistingFileWithoutCrashing() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapDeckWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appendingPathComponent("Capture.png")
        let original = Data("original".utf8)
        try CaptureDataWriter.write(original, to: target)

        #expect(throws: (any Error).self) {
            try CaptureDataWriter.write(Data("replacement".utf8), to: target)
        }
        #expect(try Data(contentsOf: target) == original)
    }

    @Test
    func outputPipelinePropagatesDiskFullAndPermissionFailures() throws {
        let context = try #require(
            CGContext(
                data: nil,
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let result = try CaptureResult(
            image: #require(context.makeImage()),
            displayID: 1,
            timestamp: Date()
        )
        let configuration = CaptureSaveConfiguration(
            format: .png,
            jpegQuality: 0.9,
            filenamePattern: "Capture",
            folderBookmark: nil
        )

        for code in [CocoaError.fileWriteOutOfSpace, CocoaError.fileWriteNoPermission] {
            #expect(throws: CocoaError.self) {
                try CaptureOutputPipeline.encodeAndWrite(
                    result,
                    to: URL(fileURLWithPath: "/unwritten/Capture.png"),
                    configuration: configuration,
                    writer: { _, _ in throw CocoaError(code) }
                )
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func fourKPNGEncodingCompletesWithinTheV1PerformanceBudget() throws {
        let context = try #require(
            CGContext(
                data: nil,
                width: 3840,
                height: 2160,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3840, height: 2160))
        let image = try #require(context.makeImage())

        let start = ContinuousClock.now
        let data = try CaptureImageEncoder.data(
            for: image,
            format: .png,
            jpegQuality: 0.9
        )
        let elapsed = start.duration(to: .now)

        #expect(!data.isEmpty)
        #expect(elapsed < .seconds(10))
    }
}
