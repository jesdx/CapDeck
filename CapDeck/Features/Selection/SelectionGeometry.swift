import CoreGraphics

enum SelectionGeometry {
    nonisolated static func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    /// Converts an AppKit screen-local rectangle (bottom-left origin) into the
    /// display-local, top-left-origin point coordinates ScreenCaptureKit uses.
    nonisolated static func screenCaptureRect(
        from appKitRect: CGRect,
        screenHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: appKitRect.minX,
            y: screenHeight - appKitRect.maxY,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }

    nonisolated static func appKitPointToQuartz(
        _ point: CGPoint,
        primaryScreenMaxY: CGFloat
    ) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenMaxY - point.y)
    }

    nonisolated static func quartzRectToAppKit(
        _ rect: CGRect,
        primaryScreenMaxY: CGFloat
    ) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Converts a point inside a display overlay (AppKit bottom-left origin)
    /// to the global Quartz coordinate space (top-left origin).
    nonisolated static func localAppKitPointToQuartz(
        _ point: CGPoint,
        displayQuartzFrame: CGRect
    ) -> CGPoint {
        CGPoint(
            x: displayQuartzFrame.minX + point.x,
            y: displayQuartzFrame.maxY - point.y
        )
    }

    /// Converts a global Quartz rectangle into display-local AppKit
    /// coordinates. This works for displays placed above, below, or left of
    /// the primary display without relying on NSScreen ordering.
    nonisolated static func quartzRectToLocalAppKit(
        _ rect: CGRect,
        displayQuartzFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: rect.minX - displayQuartzFrame.minX,
            y: displayQuartzFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
