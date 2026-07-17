import AppKit
@testable import CapDeck
import CoreGraphics
import Foundation
import Testing

@MainActor
struct PasteboardClipboardServiceTests {
    @Test
    func writesAReadableImageRepresentation() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("CapDeckTests.\(UUID().uuidString)")
        )
        let service = PasteboardClipboardService(pasteboard: pasteboard)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: 4,
                height: 5,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let image = try #require(context.makeImage())

        try service.write(
            CaptureResult(image: image, displayID: 1, timestamp: Date())
        )

        let pngData = try #require(pasteboard.data(forType: .png))
        let pngRepresentation = try #require(NSBitmapImageRep(data: pngData))
        #expect(pngRepresentation.pixelsWide == 4)
        #expect(pngRepresentation.pixelsHigh == 5)

        let tiffData = try #require(pasteboard.data(forType: .tiff))
        let tiffRepresentation = try #require(NSBitmapImageRep(data: tiffData))
        #expect(tiffRepresentation.pixelsWide == 4)
        #expect(tiffRepresentation.pixelsHigh == 5)
        #expect(pasteboard.types?.first == .png)
    }

    @Test
    func writeTextPlacesAPlainStringRepresentation() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("CapDeckTextTests.\(UUID().uuidString)")
        )
        let service = PasteboardClipboardService(pasteboard: pasteboard)

        try service.writeText("Recognized ข้อความ")

        #expect(pasteboard.string(forType: .string) == "Recognized ข้อความ")
        #expect(pasteboard.types?.first == .string)
        #expect(pasteboard.data(forType: .png) == nil)
    }

    @Test
    func losslessPNGDoesNotBlendAdjacentPixels() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("CapDeckPixelTests.\(UUID().uuidString)")
        )
        let service = PasteboardClipboardService(pasteboard: pasteboard)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: 2,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.setFillColor(NSColor.green.cgColor)
        context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
        let image = try #require(context.makeImage())

        try service.write(
            CaptureResult(image: image, displayID: 1, timestamp: Date())
        )

        let pngData = try #require(pasteboard.data(forType: .png))
        let decoded = try #require(NSBitmapImageRep(data: pngData))
        let first = try #require(decoded.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        let second = try #require(decoded.colorAt(x: 1, y: 0)?.usingColorSpace(.deviceRGB))
        #expect(first.redComponent > first.greenComponent)
        #expect(first.redComponent > first.blueComponent)
        #expect(second.greenComponent > second.redComponent)
        #expect(second.greenComponent > second.blueComponent)
        #expect(first.redComponent - second.redComponent > 0.5)
        #expect(second.greenComponent - first.greenComponent > 0.4)
    }
}
