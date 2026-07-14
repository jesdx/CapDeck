import AppKit

enum ClipboardServiceError: LocalizedError {
    case writeFailed

    var errorDescription: String? {
        "The screenshot could not be copied to the clipboard."
    }
}

@MainActor
protocol ClipboardWriting {
    func write(_ result: CaptureResult) throws
}

@MainActor
final class PasteboardClipboardService: ClipboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func write(_ result: CaptureResult) throws {
        let bitmap = NSBitmapImageRep(cgImage: result.image)
        guard
            let pngData = bitmap.representation(using: .png, properties: [:]),
            let tiffData = bitmap.representation(using: .tiff, properties: [:])
        else {
            throw ClipboardServiceError.writeFailed
        }

        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        guard
            pasteboard.setData(pngData, forType: .png),
            pasteboard.setData(tiffData, forType: .tiff)
        else {
            throw ClipboardServiceError.writeFailed
        }
    }
}
