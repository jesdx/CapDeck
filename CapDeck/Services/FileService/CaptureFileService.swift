import AppKit
import UniformTypeIdentifiers

enum CaptureSaveOutcome: Equatable {
    case skipped
    case discarded
    case saved(URL)
    case failed(String)
}

enum CaptureFileServiceError: LocalizedError {
    case noDestination
    case invalidBookmark
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .noDestination:
            "Choose a save folder in CapDeck Settings before using Always Save."
        case .invalidBookmark:
            "CapDeck can no longer access the selected save folder. Choose it again in Settings."
        case .encodingFailed:
            "CapDeck could not encode the captured image."
        }
    }
}

enum CaptureImageEncoder {
    nonisolated static func data(
        for image: CGImage,
        format: ImageFormat,
        jpegQuality: Double
    ) throws -> Data {
        let encodingImage = imageForEncoding(image, format: format)
        let bitmap = NSBitmapImageRep(cgImage: encodingImage)
        let data: Data? = switch format {
        case .png:
            bitmap.representation(using: .png, properties: [:])
        case .jpeg:
            bitmap.representation(
                using: .jpeg,
                properties: [
                    .compressionFactor: min(max(jpegQuality, 0.1), 1),
                ]
            )
        }
        guard let data else { throw CaptureFileServiceError.encodingFailed }
        return data
    }

    private nonisolated static func imageForEncoding(
        _ image: CGImage,
        format: ImageFormat
    ) -> CGImage {
        guard format == .jpeg else { return image }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { return image }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }
}

enum CollisionSafeFileURL {
    nonisolated static func make(
        from proposedURL: URL,
        fileManager: FileManager = .default
    ) -> URL {
        guard fileManager.fileExists(atPath: proposedURL.path) else { return proposedURL }
        let folder = proposedURL.deletingLastPathComponent()
        let baseName = proposedURL.deletingPathExtension().lastPathComponent
        let pathExtension = proposedURL.pathExtension
        var counter = 2

        while true {
            let candidate =
                folder
                    .appendingPathComponent("\(baseName)-\(counter)")
                    .appendingPathExtension(pathExtension)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}

enum CaptureDataWriter {
    nonisolated static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .withoutOverwriting)
    }
}

enum CaptureOutputPipeline {
    nonisolated static func encodeAndWrite(
        _ result: CaptureResult,
        to url: URL,
        configuration: CaptureSaveConfiguration,
        writer: (Data, URL) throws -> Void = CaptureDataWriter.write
    ) throws {
        let data = try CaptureImageEncoder.data(
            for: result.image,
            format: configuration.format,
            jpegQuality: configuration.jpegQuality
        )
        try writer(data, url)
    }
}

@MainActor
protocol CaptureSaving {
    func process(
        _ result: CaptureResult,
        policy: SavePolicy,
        configuration: CaptureSaveConfiguration
    ) async -> CaptureSaveOutcome

    func saveAs(
        _ result: CaptureResult,
        configuration: CaptureSaveConfiguration,
        presentingWindow: NSWindow?
    ) async -> CaptureSaveOutcome
}

extension CaptureSaving {
    func saveAs(
        _ result: CaptureResult,
        configuration: CaptureSaveConfiguration
    ) async -> CaptureSaveOutcome {
        await saveAs(
            result,
            configuration: configuration,
            presentingWindow: nil
        )
    }
}

@MainActor
final class CaptureFileService: CaptureSaving {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func process(
        _ result: CaptureResult,
        policy: SavePolicy,
        configuration: CaptureSaveConfiguration
    ) async -> CaptureSaveOutcome {
        switch policy {
        case .never:
            return .skipped
        case .always:
            do {
                let url = try await saveAutomatically(result, configuration: configuration)
                return .saved(url)
            } catch {
                report(error)
                return .failed(error.localizedDescription)
            }
        case .askEveryTime:
            return await saveAs(result, configuration: configuration)
        }
    }

    func saveAs(
        _ result: CaptureResult,
        configuration: CaptureSaveConfiguration,
        presentingWindow: NSWindow?
    ) async -> CaptureSaveOutcome {
        do {
            let filename = try FilenamePattern.render(
                configuration.filenamePattern,
                date: result.timestamp
            )
            let panel = NSSavePanel()
            panel.title = "Save CapDeck Capture"
            panel.prompt = "Save"
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.allowedContentTypes = [contentType(for: configuration.format)]
            panel.nameFieldStringValue = "\(filename).\(configuration.format.fileExtension)"

            if let bookmark = configuration.folderBookmark,
               let folder = try? resolveFolder(bookmark)
            {
                panel.directoryURL = folder
            }

            let response = await run(panel, presentingWindow: presentingWindow)
            guard response == .OK, let selectedURL = panel.url else {
                return .discarded
            }

            let targetURL = normalizedURL(selectedURL, format: configuration.format)
            let uniqueTarget = CollisionSafeFileURL.make(
                from: targetURL,
                fileManager: fileManager
            )
            try await write(result, to: uniqueTarget, configuration: configuration)
            return .saved(uniqueTarget)
        } catch {
            report(error)
            return .failed(error.localizedDescription)
        }
    }

    private func saveAutomatically(
        _ result: CaptureResult,
        configuration: CaptureSaveConfiguration
    ) async throws -> URL {
        guard let bookmark = configuration.folderBookmark else {
            throw CaptureFileServiceError.noDestination
        }
        let folder = try resolveFolder(bookmark)
        let didAccess = folder.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                folder.stopAccessingSecurityScopedResource()
            }
        }

        let filename = try FilenamePattern.render(
            configuration.filenamePattern,
            date: result.timestamp
        )
        let proposedURL =
            folder
                .appendingPathComponent(filename, isDirectory: false)
                .appendingPathExtension(configuration.format.fileExtension)
        let targetURL = CollisionSafeFileURL.make(
            from: proposedURL,
            fileManager: fileManager
        )
        try await write(result, to: targetURL, configuration: configuration)
        return targetURL
    }

    private func write(
        _ result: CaptureResult,
        to url: URL,
        configuration: CaptureSaveConfiguration
    ) async throws {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        try await Task.detached(priority: .userInitiated) {
            try CaptureOutputPipeline.encodeAndWrite(
                result,
                to: url,
                configuration: configuration
            )
        }.value
    }

    private func resolveFolder(_ bookmark: Data) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard !isStale else { throw CaptureFileServiceError.invalidBookmark }
        return url
    }

    private func normalizedURL(_ url: URL, format: ImageFormat) -> URL {
        guard url.pathExtension.lowercased() != format.fileExtension else { return url }
        return url.deletingPathExtension().appendingPathExtension(format.fileExtension)
    }

    private func contentType(for format: ImageFormat) -> UTType {
        switch format {
        case .png: .png
        case .jpeg: .jpeg
        }
    }

    private func run(
        _ panel: NSSavePanel,
        presentingWindow: NSWindow?
    ) async -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)

        return await withCheckedContinuation { continuation in
            if let presentingWindow, presentingWindow.isVisible {
                presentingWindow.makeKeyAndOrderFront(nil)
                panel.beginSheetModal(for: presentingWindow) { response in
                    continuation.resume(returning: response)
                }
            } else {
                // Ask Every Time can run before Preview exists. Keep the
                // app-modal panel above CapDeck's floating utility windows.
                panel.level = .floating
                panel.begin { response in
                    continuation.resume(returning: response)
                }
            }
        }
    }

    private func report(_ error: Error) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Capture could not be saved"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.window.level = .floating
            alert.runModal()
        }
    }
}
