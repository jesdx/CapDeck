import CoreGraphics
import Foundation
import ScreenCaptureKit

enum ScreenCaptureServiceError: LocalizedError {
    case noDisplayAvailable
    case displayUnavailable
    case invalidRegion
    case windowUnavailable

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            "No display is currently available to capture."
        case .displayUnavailable:
            "The selected display is no longer available."
        case .invalidRegion:
            "The selected region is no longer valid."
        case .windowUnavailable:
            "The selected window is no longer available."
        }
    }
}

enum CapturePixelSizing {
    nonisolated static func pixels(for pointSize: CGSize, scale: CGFloat) -> CGSize {
        let resolvedScale = max(1, scale)
        return CGSize(
            width: max(1, (pointSize.width * resolvedScale).rounded()),
            height: max(1, (pointSize.height * resolvedScale).rounded())
        )
    }

    /// Aligns both edges of a display-local point rectangle to physical pixel
    /// boundaries. Passing a fractional sourceRect to ScreenCaptureKit causes
    /// it to resample the entire screenshot, which visibly softens text.
    nonisolated static func pixelAlignedSourceRect(
        _ rect: CGRect,
        within displayBounds: CGRect,
        scale: CGFloat
    ) -> CGRect {
        let resolvedScale = max(1, scale)
        let clipped = rect.intersection(displayBounds)
        guard !clipped.isNull, !clipped.isEmpty else { return .null }

        let minX = (clipped.minX * resolvedScale).rounded(.down)
        let minY = (clipped.minY * resolvedScale).rounded(.down)
        let maxX = (clipped.maxX * resolvedScale).rounded(.up)
        let maxY = (clipped.maxY * resolvedScale).rounded(.up)

        let aligned = CGRect(
            x: minX / resolvedScale,
            y: minY / resolvedScale,
            width: (maxX - minX) / resolvedScale,
            height: (maxY - minY) / resolvedScale
        )
        return aligned.intersection(displayBounds)
    }
}

@MainActor
protocol ScreenCapturing {
    func capture(_ request: CaptureRequest) async throws -> CaptureResult
}

@MainActor
final class ScreenCaptureService: ScreenCapturing {
    func capture(_ request: CaptureRequest) async throws -> CaptureResult {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        switch request.mode {
        case .fullScreen, .region:
            return try await captureDisplay(request: request, content: content)
        case .window:
            return try await captureWindow(request: request, content: content)
        }
    }

    private func captureDisplay(
        request: CaptureRequest,
        content: SCShareableContent
    ) async throws -> CaptureResult {
        let requestedDisplayID = request.displayID ?? CGMainDisplayID()
        let display: SCDisplay

        if request.displayID != nil {
            guard
                let exactDisplay = content.displays.first(where: {
                    $0.displayID == requestedDisplayID
                })
            else {
                throw ScreenCaptureServiceError.displayUnavailable
            }
            display = exactDisplay
        } else if let mainDisplay = content.displays.first(where: {
            $0.displayID == requestedDisplayID
        }) ?? content.displays.first {
            display = mainDisplay
        } else {
            throw ScreenCaptureServiceError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let contentInfo = SCShareableContent.info(for: filter)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(contentInfo.pointPixelScale)
        let displayBounds = CGRect(
            x: 0,
            y: 0,
            width: display.width,
            height: display.height
        )

        if request.mode == .region {
            guard let requestedRect = request.sourceRect else {
                throw ScreenCaptureServiceError.invalidRegion
            }
            let sourceRect = CapturePixelSizing.pixelAlignedSourceRect(
                requestedRect,
                within: displayBounds,
                scale: scale
            )
            guard sourceRect.width >= 1, sourceRect.height >= 1 else {
                throw ScreenCaptureServiceError.invalidRegion
            }
            configuration.sourceRect = sourceRect
            let pixelSize = CapturePixelSizing.pixels(
                for: sourceRect.size,
                scale: scale
            )
            configuration.width = Int(pixelSize.width)
            configuration.height = Int(pixelSize.height)
        } else {
            let pixelSize = CapturePixelSizing.pixels(
                for: CGSize(width: display.width, height: display.height),
                scale: scale
            )
            configuration.width = Int(pixelSize.width)
            configuration.height = Int(pixelSize.height)
        }

        configureCommonProperties(configuration)
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        return CaptureResult(
            image: image,
            displayID: display.displayID,
            timestamp: Date()
        )
    }

    private func captureWindow(
        request: CaptureRequest,
        content: SCShareableContent
    ) async throws -> CaptureResult {
        guard
            let windowID = request.windowID,
            let window = content.windows.first(where: { $0.windowID == windowID })
        else {
            throw ScreenCaptureServiceError.windowUnavailable
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let contentInfo = SCShareableContent.info(for: filter)
        let configuration = SCStreamConfiguration()
        let nativeScale = CGFloat(contentInfo.pointPixelScale)
        let pixelSize = CapturePixelSizing.pixels(
            for: contentInfo.contentRect.size,
            scale: nativeScale
        )
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.ignoreShadowsSingleWindow = false
        configureCommonProperties(configuration)

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        return CaptureResult(
            image: image,
            displayID: content.displays.first(where: {
                CGDisplayBounds($0.displayID).intersects(window.frame)
            })?.displayID ?? CGMainDisplayID(),
            timestamp: Date()
        )
    }

    private func configureCommonProperties(_ configuration: SCStreamConfiguration) {
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.captureResolution = .best
        configuration.shouldBeOpaque = false
    }
}
