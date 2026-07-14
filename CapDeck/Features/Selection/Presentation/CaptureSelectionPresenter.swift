import AppKit
import Carbon.HIToolbox
import CoreGraphics

enum CaptureSelectionError: LocalizedError {
    case noDisplaysAvailable
    case noWindowsAvailable

    var errorDescription: String? {
        switch self {
        case .noDisplaysAvailable:
            "No display is currently available for selection."
        case .noWindowsAvailable:
            "No visible window is currently available to capture."
        }
    }
}

@MainActor
protocol CaptureSelectionPresenting {
    func availableWindows() -> [CaptureWindowOption]
    func selectRegion() async throws -> CaptureRequest?
    func selectWindow() async throws -> CaptureRequest?
    func selectDisplay() async throws -> CaptureRequest?
}

@MainActor
final class CaptureSelectionPresenter: CaptureSelectionPresenting {
    private let displayService: DisplayProviding
    private var activeSession: CaptureSelectionSession?

    init(displayService: DisplayProviding = DisplayService()) {
        self.displayService = displayService
    }

    func availableWindows() -> [CaptureWindowOption] {
        WindowCandidate.visibleWindows().map(\.option)
    }

    func selectRegion() async throws -> CaptureRequest? {
        guard !displayService.availableDisplays().isEmpty else {
            throw CaptureSelectionError.noDisplaysAvailable
        }
        return await beginSession(mode: .region, windowCandidates: [])
    }

    func selectWindow() async throws -> CaptureRequest? {
        let candidates = WindowCandidate.visibleWindows()
        guard !candidates.isEmpty else {
            throw CaptureSelectionError.noWindowsAvailable
        }
        return await beginSession(mode: .window, windowCandidates: candidates)
    }

    func selectDisplay() async throws -> CaptureRequest? {
        guard !displayService.availableDisplays().isEmpty else {
            throw CaptureSelectionError.noDisplaysAvailable
        }
        return await beginSession(mode: .fullScreen, windowCandidates: [])
    }

    private func beginSession(
        mode: CaptureMode,
        windowCandidates: [WindowCandidate]
    ) async -> CaptureRequest? {
        guard activeSession == nil else { return nil }

        return await withCheckedContinuation { continuation in
            let session = CaptureSelectionSession(
                mode: mode,
                displays: displayService.availableDisplays(),
                windowCandidates: windowCandidates
            ) { [weak self] request in
                self?.activeSession = nil
                continuation.resume(returning: request)
            }
            activeSession = session
            session.start()
        }
    }
}

private struct WindowCandidate: Equatable {
    let windowID: CGWindowID
    let quartzFrame: CGRect
    let applicationName: String
    let windowTitle: String

    var option: CaptureWindowOption {
        CaptureWindowOption(
            id: windowID,
            applicationName: applicationName,
            windowTitle: windowTitle
        )
    }

    static func visibleWindows() -> [WindowCandidate] {
        guard
            let rawWindows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return []
        }

        let currentProcessID = getpid()

        return rawWindows.compactMap { info in
            guard
                let number = info[kCGWindowNumber as String] as? NSNumber,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                let x = bounds["X"] as? NSNumber,
                let y = bounds["Y"] as? NSNumber,
                let width = bounds["Width"] as? NSNumber,
                let height = bounds["Height"] as? NSNumber,
                let layer = info[kCGWindowLayer as String] as? NSNumber,
                let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                let applicationName = info[kCGWindowOwnerName as String] as? String,
                !applicationName.isEmpty,
                layer.intValue == 0,
                ownerPID.int32Value != currentProcessID,
                width.doubleValue >= 80,
                height.doubleValue >= 50
            else {
                return nil
            }

            let frame = CGRect(
                x: x.doubleValue,
                y: y.doubleValue,
                width: width.doubleValue,
                height: height.doubleValue
            )

            return WindowCandidate(
                windowID: CGWindowID(number.uint32Value),
                quartzFrame: frame,
                applicationName: applicationName,
                windowTitle: info[kCGWindowName as String] as? String ?? ""
            )
        }
    }
}

@MainActor
private final class CaptureSelectionSession {
    private let mode: CaptureMode
    private let displays: [CaptureDisplay]
    private let windowCandidates: [WindowCandidate]
    private let completion: (CaptureRequest?) -> Void
    private let previousApplication: NSRunningApplication?
    private var panels: [SelectionPanel] = []
    private var views: [SelectionOverlayView] = []
    private var isFinished = false
    private var cursorWasPushed = false
    private var hoveredWindow: WindowCandidate?
    private var keyboardWindowIndex: Int?
    private var escapeMonitor: Any?

    init(
        mode: CaptureMode,
        displays: [CaptureDisplay],
        windowCandidates: [WindowCandidate],
        completion: @escaping (CaptureRequest?) -> Void
    ) {
        self.mode = mode
        self.displays = displays
        self.windowCandidates = windowCandidates
        self.completion = completion
        previousApplication = NSWorkspace.shared.frontmostApplication
    }

    func start() {
        // A global shortcut arrives while another app owns focus. Activating the
        // NSApplication (rather than only its running-process wrapper) lets the
        // borderless selection panels become key and receive the first drag.
        NSApp.activate(ignoringOtherApps: true)

        for display in displays {
            let panel = SelectionPanel(
                contentRect: CGRect(origin: .zero, size: display.appKitFrame.size),
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: display.screen
            )
            panel.setFrame(display.appKitFrame, display: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = true
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle,
            ]

            let view = SelectionOverlayView(
                frame: CGRect(origin: .zero, size: display.appKitFrame.size),
                display: display,
                mode: mode,
                onRegionSelected: { [weak self] displayID, rect in
                    self?.finish(
                        with: CaptureRequest(
                            mode: .region,
                            displayID: displayID,
                            sourceRect: rect
                        )
                    )
                },
                onWindowHover: { [weak self] point in
                    self?.updateHoveredWindow(at: point)
                },
                onWindowSelected: { [weak self] in
                    self?.selectHoveredWindow()
                },
                onDisplaySelected: { [weak self] displayID in
                    self?.finish(
                        with: CaptureRequest(
                            mode: .fullScreen,
                            displayID: displayID
                        )
                    )
                },
                onCancel: { [weak self] in
                    self?.finish(with: nil)
                }
            )

            panel.contentView = view
            panels.append(panel)
            views.append(view)
            panel.orderFrontRegardless()
        }

        if mode == .region {
            NSCursor.crosshair.push()
            cursorWasPushed = true
        }

        if mode == .window, !windowCandidates.isEmpty {
            keyboardWindowIndex = 0
            hoveredWindow = windowCandidates[0]
            views.forEach { $0.hoveredWindowFrame = windowCandidates[0].quartzFrame }
        }

        if let firstPanel = panels.first, let firstView = views.first {
            firstPanel.makeKeyAndOrderFront(nil)
            firstPanel.makeFirstResponder(firstView)
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            if event.keyCode == 53 {
                self?.finish(with: nil)
                return nil
            }
            if self?.mode == .window,
               [UInt16(kVK_LeftArrow), UInt16(kVK_UpArrow)].contains(event.keyCode)
            {
                self?.moveKeyboardWindowSelection(by: -1)
                return nil
            }
            if self?.mode == .window,
               [UInt16(kVK_RightArrow), UInt16(kVK_DownArrow)].contains(event.keyCode)
            {
                self?.moveKeyboardWindowSelection(by: 1)
                return nil
            }
            return event
        }
    }

    private func moveKeyboardWindowSelection(by offset: Int) {
        guard !windowCandidates.isEmpty else { return }
        let current = keyboardWindowIndex ?? -1
        let count = windowCandidates.count
        let next = (current + offset + count) % count
        keyboardWindowIndex = next
        hoveredWindow = windowCandidates[next]
        views.forEach { $0.hoveredWindowFrame = windowCandidates[next].quartzFrame }
        NSAccessibility.post(element: views.first as Any, notification: .valueChanged)
    }

    private func updateHoveredWindow(at quartzPoint: CGPoint) {
        let candidate = windowCandidates.first { $0.quartzFrame.contains(quartzPoint) }
        guard candidate != hoveredWindow else { return }
        hoveredWindow = candidate
        views.forEach { $0.hoveredWindowFrame = candidate?.quartzFrame }
    }

    private func selectHoveredWindow() {
        guard let hoveredWindow else { return }
        finish(
            with: CaptureRequest(
                mode: .window,
                windowID: hoveredWindow.windowID
            )
        )
    }

    private func finish(with request: CaptureRequest?) {
        guard !isFinished else { return }
        isFinished = true

        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        views.removeAll()

        if cursorWasPushed {
            NSCursor.pop()
        }

        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }

        if let previousApplication,
           previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier
        {
            previousApplication.activate(options: [])
        }

        completion(request)
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
private final class SelectionOverlayView: NSView {
    private let selectionDisplay: CaptureDisplay
    private let mode: CaptureMode
    private let onRegionSelected: (CGDirectDisplayID, CGRect) -> Void
    private let onWindowHover: (CGPoint) -> Void
    private let onWindowSelected: () -> Void
    private let onDisplaySelected: (CGDirectDisplayID) -> Void
    private let onCancel: () -> Void

    private var dragStart: CGPoint?
    private var selectionRect: CGRect?
    private var pointerLocation: CGPoint?
    private var trackingAreaReference: NSTrackingArea?

    var hoveredWindowFrame: CGRect? {
        didSet { needsDisplay = true }
    }

    init(
        frame: CGRect,
        display: CaptureDisplay,
        mode: CaptureMode,
        onRegionSelected: @escaping (CGDirectDisplayID, CGRect) -> Void,
        onWindowHover: @escaping (CGPoint) -> Void,
        onWindowSelected: @escaping () -> Void,
        onDisplaySelected: @escaping (CGDirectDisplayID) -> Void,
        onCancel: @escaping () -> Void
    ) {
        selectionDisplay = display
        self.mode = mode
        self.onRegionSelected = onRegionSelected
        self.onWindowHover = onWindowHover
        self.onWindowSelected = onWindowSelected
        self.onDisplaySelected = onDisplaySelected
        self.onCancel = onCancel
        super.init(frame: frame)
        setAccessibilityElement(true)
        switch mode {
        case .region:
            setAccessibilityRole(.group)
            setAccessibilityLabel("Region capture selection")
            setAccessibilityHelp("Drag to select a region. Press Escape to cancel.")
        case .window:
            setAccessibilityRole(.button)
            setAccessibilityLabel("Window capture selection")
            setAccessibilityHelp("Use arrow keys to choose a window, Return to capture, or Escape to cancel.")
        case .fullScreen:
            setAccessibilityRole(.button)
            setAccessibilityLabel("Capture this display")
            setAccessibilityHelp("Press Return or Space to capture this display, or Escape to cancel.")
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        } else if [UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter), UInt16(kVK_Space)]
            .contains(event.keyCode)
        {
            switch mode {
            case .window:
                onWindowSelected()
            case .fullScreen:
                onDisplaySelected(selectionDisplay.id)
            case .region:
                NSSound.beep()
            }
        } else {
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        switch mode {
        case .window:
            onWindowSelected()
            return true
        case .fullScreen:
            onDisplaySelected(selectionDisplay.id)
            return true
        case .region:
            return false
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        pointerLocation = localPoint

        if mode == .window {
            updateWindowHover(with: event)
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if mode == .window {
            updateWindowHover(with: event)
            return
        }

        if mode == .fullScreen {
            // Resolve on mouse-down so a panel on a non-key secondary display
            // accepts the very first click without waiting for a mouse-up event.
            onDisplaySelected(selectionDisplay.id)
            return
        }

        let point = clamped(convert(event.locationInWindow, from: nil))
        dragStart = point
        pointerLocation = point
        selectionRect = CGRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .region, let dragStart else { return }
        let point = clamped(convert(event.locationInWindow, from: nil))
        pointerLocation = point
        selectionRect = SelectionGeometry.normalizedRect(from: dragStart, to: point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if mode == .window {
            // A non-activating overlay may receive the click without a prior
            // mouseMoved event, so resolve the target again before selecting.
            updateWindowHover(with: event)
            onWindowSelected()
            return
        }

        guard
            let dragStart
        else { return }

        let point = clamped(convert(event.locationInWindow, from: nil))
        let rect = SelectionGeometry.normalizedRect(from: dragStart, to: point)
        self.dragStart = nil

        guard rect.width >= 3, rect.height >= 3 else {
            selectionRect = nil
            needsDisplay = true
            return
        }

        let captureRect = SelectionGeometry.screenCaptureRect(
            from: rect,
            screenHeight: bounds.height
        )
        onRegionSelected(selectionDisplay.id, captureRect)
    }

    private func updateWindowHover(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        onWindowHover(
            SelectionGeometry.localAppKitPointToQuartz(
                localPoint,
                displayQuartzFrame: selectionDisplay.quartzFrame
            )
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let cutout = currentCutoutRect()
        drawDimmingLayer(cutout: cutout)

        let outlineRect =
            mode == .fullScreen
                ? bounds.insetBy(dx: 3, dy: 3)
                : cutout
        if let outlineRect, !outlineRect.isEmpty {
            NSColor.systemOrange.setStroke()
            let outline = NSBezierPath(roundedRect: outlineRect, xRadius: 4, yRadius: 4)
            outline.lineWidth = 2
            outline.stroke()
        }

        if mode == .region {
            drawCrosshair()
            if let selectionRect, selectionRect.width >= 3, selectionRect.height >= 3 {
                drawSizeBadge(for: selectionRect)
            }
        }

        drawInstruction()
    }

    private func currentCutoutRect() -> CGRect? {
        if mode == .region {
            return selectionRect
        }
        if mode == .fullScreen {
            return nil
        }
        guard let hoveredWindowFrame else { return nil }
        let intersection = hoveredWindowFrame.intersection(selectionDisplay.quartzFrame)
        guard !intersection.isNull else { return nil }
        let appKitFrame = SelectionGeometry.quartzRectToLocalAppKit(
            intersection,
            displayQuartzFrame: selectionDisplay.quartzFrame
        )
        return appKitFrame.intersection(bounds)
    }

    private func drawDimmingLayer(cutout: CGRect?) {
        let path = NSBezierPath(rect: bounds)
        if let cutout, !cutout.isEmpty {
            path.appendRect(cutout)
            path.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.42).setFill()
        path.fill()
    }

    private func drawCrosshair() {
        guard dragStart == nil, let pointerLocation else { return }
        NSColor.white.withAlphaComponent(0.55).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 0.75
        path.move(to: CGPoint(x: pointerLocation.x, y: bounds.minY))
        path.line(to: CGPoint(x: pointerLocation.x, y: bounds.maxY))
        path.move(to: CGPoint(x: bounds.minX, y: pointerLocation.y))
        path.line(to: CGPoint(x: bounds.maxX, y: pointerLocation.y))
        path.stroke()
    }

    private func drawInstruction() {
        let text: String
        switch mode {
        case .region:
            text = "Drag to capture  •  Esc to cancel"
        case .window:
            text = "Click a window to capture  •  Esc to cancel"
        case .fullScreen:
            let pixels = selectionDisplay.nativePixelSize
            text = "Click \(selectionDisplay.name)  •  \(Int(pixels.width)) × \(Int(pixels.height))  •  Esc to cancel"
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(
            x: bounds.midX - size.width / 2 - 14,
            y: bounds.maxY - size.height - 30,
            width: size.width + 28,
            height: size.height + 12
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        text.draw(
            at: CGPoint(x: rect.minX + 14, y: rect.minY + 6),
            withAttributes: attributes
        )
    }

    private func drawSizeBadge(for rect: CGRect) {
        let scale = selectionDisplay.nativeScale
        let text = "\(Int((rect.width * scale).rounded())) × \(Int((rect.height * scale).rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        var origin = CGPoint(x: rect.minX, y: rect.minY - size.height - 14)
        if origin.y < 8 {
            origin.y = rect.maxY + 8
        }
        let badge = CGRect(
            x: min(max(8, origin.x), bounds.maxX - size.width - 24),
            y: min(origin.y, bounds.maxY - size.height - 20),
            width: size.width + 16,
            height: size.height + 8
        )
        NSColor.systemOrange.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 6, yRadius: 6).fill()
        text.draw(
            at: CGPoint(x: badge.minX + 8, y: badge.minY + 4),
            withAttributes: attributes
        )
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(bounds.minX, point.x), bounds.maxX),
            y: min(max(bounds.minY, point.y), bounds.maxY)
        )
    }
}
