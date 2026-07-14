import CoreGraphics

struct CaptureRequest: Equatable, Sendable {
    let mode: CaptureMode
    let displayID: CGDirectDisplayID?
    let sourceRect: CGRect?
    let windowID: CGWindowID?

    init(
        mode: CaptureMode,
        displayID: CGDirectDisplayID? = nil,
        sourceRect: CGRect? = nil,
        windowID: CGWindowID? = nil
    ) {
        self.mode = mode
        self.displayID = displayID
        self.sourceRect = sourceRect
        self.windowID = windowID
    }
}
