import AppKit
import CoreGraphics

@MainActor
struct CaptureDisplay: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let appKitFrame: CGRect
    let quartzFrame: CGRect
    let nativeScale: CGFloat
    let screen: NSScreen

    var logicalSize: CGSize { appKitFrame.size }

    var nativePixelSize: CGSize {
        CGSize(
            width: (logicalSize.width * nativeScale).rounded(),
            height: (logicalSize.height * nativeScale).rounded()
        )
    }
}

@MainActor
protocol DisplayProviding {
    func availableDisplays() -> [CaptureDisplay]
    func displayUnderPointer() -> CaptureDisplay?
}

@MainActor
final class DisplayService: DisplayProviding {
    func availableDisplays() -> [CaptureDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let displayID = screen.displayID else { return nil }
            return CaptureDisplay(
                id: displayID,
                name: screen.localizedName,
                appKitFrame: screen.frame,
                quartzFrame: CGDisplayBounds(displayID),
                nativeScale: screen.backingScaleFactor,
                screen: screen
            )
        }
    }

    func displayUnderPointer() -> CaptureDisplay? {
        let pointer = NSEvent.mouseLocation
        return availableDisplays().first { $0.appKitFrame.contains(pointer) }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }
}
