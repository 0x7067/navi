import AppKit
import Carbon.HIToolbox
import NaviCore

/// A full-screen selection, one overlay window per display. The overlay shows at once over the live
/// screen; the frozen screen images arrive a moment later (`freeze`) and are what gets cropped.
///
/// Area mode: drag a box. Edges snap to window edges. A magnifier shows the pixels under the cursor.
/// Window mode: hover to highlight a window, click to pick it. Space switches modes. Esc cancels.
@MainActor
final class SelectionSession {
    enum Mode { case area, window }

    /// What happens with the picked area or window.
    enum Purpose: Equatable {
        case screenshot, text, scroll, record
    }

    enum Outcome {
        /// `rect` is the selection in display-local points with the origin at the top left.
        case area(CapturedImage, NSScreen, rect: CGRect)
        case window(CGWindowID, NSScreen)
        case fullscreen(NSScreen)
        case cancelled
    }

    private(set) var mode: Mode
    var purpose: Purpose = .screenshot {
        didSet {
            if purpose == .text || purpose == .scroll { mode = .area }
            refresh()
            // Record picked with an area already held: go straight to the record bar. Its
            // Record Video and Record GIF buttons are the one place that starts a recording.
            if purpose == .record, oldValue != .record, hasHeldSelection { confirmHeldSelection() }
        }
    }

    /// Seconds to wait before the shot. 0 is off.
    var timer = 0
    /// Shows the all-in-one bar with every mode.
    var showsModeBar = false
    var canRecord = false
    /// All-in-one: an area stays on screen after the drag, so it can be moved, resized, and then
    /// captured from the bar (or with Return), or handed to the record bar by picking Record.
    /// Otherwise the drag ends the selection. In Record mode the drag goes straight to the record bar.
    var holdsSelection = false
    /// The overlay that holds the finished area, while `holdsSelection` is on.
    private weak var heldOverlay: OverlayView?
    var hasHeldSelection: Bool { heldOverlay != nil }
    private var modeBar: ModeBarPanel?
    /// App windows in Cocoa global coordinates, front to back.
    let windows: [OnScreenWindow]
    private var overlays: [OverlayWindow] = []
    private var keyMonitor: Any?
    /// Esc, Space, and Return as Carbon hot keys while the overlay is up. macOS may refuse to make
    /// Navi the active app, and then no key event reaches the overlay or the local monitor.
    private var sessionKeys: [HotKey] = []
    private var completion: ((Outcome) -> Void)?

    init(screens: [NSScreen], mode: Mode, windows: [OnScreenWindow], completion: @escaping (Outcome) -> Void) {
        self.mode = mode
        self.windows = windows
        self.completion = completion
        overlays = screens.map { screen in
            OverlayWindow(screen: screen, view: OverlayView(session: nil, screen: screen))
        }
        for overlay in overlays { overlay.overlayView.session = self }
    }

    /// Gives each overlay its frozen screen image.
    func freeze(_ images: [(NSScreen, CapturedImage)]) {
        for (screen, captured) in images {
            overlays.first { $0.overlayView.screen == screen }?.overlayView.captured = captured
        }
    }

    func begin() {
        let mouseScreen = NSScreen.underMouse
        for overlay in overlays {
            overlay.orderFrontRegardless()
            if overlay.overlayView.screen == mouseScreen {
                overlay.makeKey()
                overlay.makeFirstResponder(overlay.overlayView)
            }
        }
        if showsModeBar, let mouseScreen {
            let bar = ModeBarPanel(session: self, screen: mouseScreen)
            bar.orderFrontRegardless()
            modeBar = bar
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch Int(event.keyCode) {
            case kVK_Escape: finish(.cancelled)
            case kVK_Space: toggleMode()
            case kVK_Return, kVK_ANSI_KeypadEnter: confirmHeldSelection()
            default: break
            }
            return nil
        }
        sessionKeys = [
            HotKey(keyCode: UInt32(kVK_Escape), modifiers: 0) { [weak self] in self?.finish(.cancelled) },
            HotKey(keyCode: UInt32(kVK_Space), modifiers: 0) { [weak self] in self?.toggleMode() },
            HotKey(keyCode: UInt32(kVK_Return), modifiers: 0) { [weak self] in self?.confirmHeldSelection() },
            HotKey(keyCode: UInt32(kVK_ANSI_KeypadEnter), modifiers: 0) { [weak self] in self?.confirmHeldSelection() },
        ].compactMap { $0 }
        refresh()
    }

    func toggleMode() {
        guard purpose == .screenshot || purpose == .record else { return }
        setMode(mode == .area ? .window : .area)
    }

    func setMode(_ mode: Mode) {
        self.mode = mode
        for overlay in overlays { overlay.overlayView.resetDrag() }
        heldOverlay = nil
        refresh()
    }

    /// An overlay now holds an area (or nil: it let go of it). Only one display holds an area.
    func holdChanged(_ overlay: OverlayView?) {
        if let overlay {
            for other in overlays where other.overlayView !== overlay { other.overlayView.resetDrag() }
        }
        heldOverlay = overlay
        refresh()
    }

    /// Captures, records, or reads the held area, by the purpose picked in the bar.
    func confirmHeldSelection() {
        heldOverlay?.finishSelection()
    }

    /// The text that tells the user what to do now.
    var hint: String {
        if hasHeldSelection {
            let verb = switch purpose {
            case .screenshot: "capture"
            case .text: "copy the text"
            case .scroll: "start scrolling"
            case .record: "open the record bar"
            }
            return "Return to \(verb)  ·  Drag inside to move, corners to resize  ·  Esc to cancel"
        }
        let action = switch purpose {
        case .screenshot: mode == .area ? "Drag to capture" : "Click a window"
        case .text: "Drag over text to copy it"
        case .scroll: "Drag over the area to scroll"
        case .record: mode == .area ? "Drag the area to record" : "Click a window to record"
        }
        let space = purpose == .text || purpose == .scroll ? "" : (mode == .area ? "  ·  Space for window" : "  ·  Space for area")
        return action + space + "  ·  Esc to cancel"
    }

    func refresh() {
        (mode == .area ? NSCursor.crosshair : OverlayView.cameraCursor).set()
        modeBar?.refresh()
        for overlay in overlays {
            overlay.overlayView.needsDisplay = true
            overlay.invalidateCursorRects(for: overlay.overlayView)
        }
    }

    func finish(_ outcome: Outcome) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        for key in sessionKeys { key.unregister() }
        sessionKeys = []
        for overlay in overlays { overlay.orderOut(nil) }
        overlays = []
        modeBar?.orderOut(nil)
        modeBar = nil
        let completion = completion
        self.completion = nil
        completion?(outcome)
    }
}

/// A non-activating panel: it takes the keys (Esc, Space) and the mouse without bringing Navi to the
/// front, so other Navi windows (an open markup editor) stay where they are.
final class OverlayWindow: NSPanel {
    let overlayView: OverlayView

    init(screen: NSScreen, view: OverlayView) {
        overlayView = view
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        setFrame(screen.frame, display: false)
        level = .screenSaver
        // Clear until the frozen image arrives, so the live screen shows through at once.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = view
    }

    override var canBecomeKey: Bool { true }
}

final class OverlayView: NSView {
    weak var session: SelectionSession?
    let screen: NSScreen
    /// The frozen screen. Nil for the first moment, while it is being taken.
    var captured: CapturedImage? {
        didSet {
            needsDisplay = true
            guard captured != nil, let pending = pendingFinish else { return }
            pendingFinish = nil
            pending()
        }
    }

    /// A selection finished before the frozen image arrived. It runs when the image comes.
    private var pendingFinish: (() -> Void)?

    private var mouse: CGPoint?
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    private static let dim = NSColor.black.withAlphaComponent(0.35)

    /// Window mode cursor: a camera, like the macOS screenshot tool. Black symbol with a white outline.
    static let cameraCursor: NSCursor = {
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Camera")?
            .withSymbolConfiguration(config)
        else { return .arrow }
        let pad: CGFloat = 2
        let size = CGSize(width: symbol.size.width + pad * 2, height: symbol.size.height + pad * 2)
        let tinted = { (color: NSColor) in
            NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
        }
        let white = tinted(.white)
        let black = tinted(.black)
        let image = NSImage(size: size, flipped: false) { _ in
            for dx in [-1.5, 0, 1.5] {
                for dy in [-1.5, 0, 1.5] where dx != 0 || dy != 0 {
                    white.draw(at: CGPoint(x: pad + dx, y: pad + dy), from: .zero, operation: .sourceOver, fraction: 1)
                }
            }
            black.draw(at: CGPoint(x: pad, y: pad), from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        return NSCursor(image: image, hotSpot: CGPoint(x: size.width / 2, y: size.height / 2))
    }()
    private static let accent = NSColor.systemBlue

    init(session: SelectionSession?, screen: NSScreen) {
        self.session = session
        self.screen = screen
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var mode: SelectionSession.Mode { session?.mode ?? .area }
    private var imageSize: CGSize {
        if let captured { return CGSize(width: captured.image.width, height: captured.image.height) }
        return CGSize(width: bounds.width * screen.backingScaleFactor, height: bounds.height * screen.backingScaleFactor)
    }

    /// Backup for the session's key monitor: the key overlay also gets the keys directly.
    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape: session?.finish(.cancelled)
        case kVK_Space: session?.toggleMode()
        case kVK_Return, kVK_ANSI_KeypadEnter: session?.confirmHeldSelection()
        default: super.keyDown(with: event)
        }
    }

    func resetDrag() {
        dragStart = nil
        dragCurrent = nil
        isHolding = false
        moveStart = nil
        needsDisplay = true
    }

    /// True while this overlay holds a finished area (all-in-one only).
    private var isHolding = false
    /// Where a move of the held area started, and the area at that moment.
    private var moveStart: (point: CGPoint, rect: CGRect)?
    private static let cornerGrab: CGFloat = 10

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: mode == .area ? .crosshair : Self.cameraCursor)
    }

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        mouse = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = location(of: event)
        mouse = point
        cursor(at: point).set()
        needsDisplay = true
    }

    private func cursor(at point: CGPoint) -> NSCursor {
        guard mode == .area else { return OverlayView.cameraCursor }
        guard isHolding, let selection else { return .crosshair }
        if CaptureGeometry.oppositeCorner(of: selection, near: point, tolerance: Self.cornerGrab) != nil { return .crosshair }
        return selection.contains(point) ? .openHand : .crosshair
    }

    override func mouseDown(with event: NSEvent) {
        let point = location(of: event)
        mouse = point
        switch mode {
        case .window:
            if let window = hoveredWindow(at: point) { session?.finish(.window(window.id, screen)) }
        case .area:
            if isHolding, let selection {
                if let anchor = CaptureGeometry.oppositeCorner(of: selection, near: point, tolerance: Self.cornerGrab) {
                    // Resize: keep the far corner, drag this one.
                    dragStart = anchor
                    dragCurrent = point
                    needsDisplay = true
                    return
                }
                if selection.contains(point) {
                    moveStart = (point, selection)
                    NSCursor.closedHand.set()
                    return
                }
                // Outside the held area: start a new one.
                session?.holdChanged(nil)
                isHolding = false
            }
            dragStart = snapped(point)
            dragCurrent = dragStart
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .area, dragStart != nil else { return }
        let point = location(of: event)
        mouse = point
        if let move = moveStart {
            let rect = CaptureGeometry.moved(
                move.rect, by: CGVector(dx: point.x - move.point.x, dy: point.y - move.point.y), within: bounds
            )
            dragStart = rect.origin
            dragCurrent = CGPoint(x: rect.maxX, y: rect.maxY)
            needsDisplay = true
            return
        }
        dragCurrent = snapped(point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .area, let selection else { return }
        moveStart = nil
        guard selection.width >= 2, selection.height >= 2 else {
            resetDrag()
            if session?.holdsSelection == true, session?.purpose != .record { session?.holdChanged(nil) }
            return
        }
        if session?.holdsSelection == true {
            // All-in-one: keep the area until the bar or Return says what to do with it.
            isHolding = true
            session?.holdChanged(self)
            cursor(at: location(of: event)).set()
            return
        }
        finishSelection()
    }

    /// Ends the session with the current area. It waits for the frozen screen when needed.
    func finishSelection() {
        guard mode == .area, let selection, selection.width >= 2, selection.height >= 2 else { return }
        resetDrag()
        let finish = { [weak self] in
            guard let self, let captured else { return }
            let pixels = CaptureGeometry.pixelRect(forSelection: selection, viewSize: bounds.size, imageSize: imageSize)
            guard let cropped = captured.image.cropping(to: pixels) else { return }
            let topLeft = CGRect(x: selection.minX, y: bounds.height - selection.maxY, width: selection.width, height: selection.height)
            session?.finish(.area(CapturedImage(image: cropped, scale: captured.scale), screen, rect: topLeft))
        }
        if captured == nil { pendingFinish = finish } else { finish() }
    }

    private func location(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }

    // MARK: Geometry

    private var selection: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return CaptureGeometry.rect(from: dragStart, to: dragCurrent)
    }

    /// App window frames in this view's coordinates, front to back.
    private var localWindows: [OnScreenWindow] {
        let origin = screen.frame.origin
        return (session?.windows ?? []).map {
            OnScreenWindow(id: $0.id, frame: $0.frame.offsetBy(dx: -origin.x, dy: -origin.y))
        }
    }

    private func hoveredWindow(at point: CGPoint) -> OnScreenWindow? {
        localWindows.first { $0.frame.contains(point) }
    }

    private func snapped(_ point: CGPoint) -> CGPoint {
        let frames = localWindows.map(\.frame)
        let xs: [CGFloat] = [0, bounds.width] + frames.flatMap { frame -> [CGFloat] in [frame.minX, frame.maxX] }
        let ys: [CGFloat] = [0, bounds.height] + frames.flatMap { frame -> [CGFloat] in [frame.minY, frame.maxY] }
        return CGPoint(
            x: CaptureGeometry.snap(point.x, to: xs, tolerance: 6),
            y: CaptureGeometry.snap(point.y, to: ys, tolerance: 6)
        )
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .high
        if let captured { context.draw(captured.image, in: bounds) }

        let hole: CGRect? = switch mode {
        case .area: selection
        case .window: mouse.flatMap { hoveredWindow(at: $0)?.frame }
        }

        context.saveGState()
        context.setFillColor(Self.dim.cgColor)
        context.addRect(bounds)
        if let hole { context.addRect(hole) }
        context.fillPath(using: .evenOdd)
        context.restoreGState()

        switch mode {
        case .area:
            if let selection {
                context.setStrokeColor(NSColor.white.cgColor)
                context.setLineWidth(1)
                context.stroke(selection.insetBy(dx: -0.5, dy: -0.5))
                if isHolding { drawCornerHandles(of: selection, in: context) }
                drawSizeLabel(for: selection)
            }
            if let mouse, let captured { drawMagnifier(at: mouse, image: captured.image, in: context) }
        case .window:
            if let hole {
                context.setFillColor(Self.accent.withAlphaComponent(0.18).cgColor)
                context.fill(hole)
                context.setStrokeColor(Self.accent.cgColor)
                context.setLineWidth(3)
                context.stroke(hole.insetBy(dx: 1.5, dy: 1.5))
            }
        }

        if mouse != nil { drawModeTag() }
    }

    /// Round handles on the held area's corners: drag one to resize.
    private func drawCornerHandles(of rect: CGRect, in context: CGContext) {
        let size: CGFloat = 8
        for corner in [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
        ] {
            let dot = CGRect(x: corner.x - size / 2, y: corner.y - size / 2, width: size, height: size)
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: dot)
            context.setStrokeColor(Self.accent.cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: dot)
        }
    }

    private func drawSizeLabel(for selection: CGRect) {
        let pixels = CaptureGeometry.pixelRect(forSelection: selection, viewSize: bounds.size, imageSize: imageSize)
        let text = "\(Int(pixels.width)) × \(Int(pixels.height))"
        var origin = CGPoint(x: selection.minX, y: selection.minY - 26)
        if origin.y < 4 { origin.y = selection.maxY + 6 }
        drawPill(text, at: origin)
    }

    private func drawModeTag() {
        guard let text = session?.hint else { return }
        let size = Self.pillSize(text)
        drawPill(text, at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.height - 70))
    }

    private func drawMagnifier(at point: CGPoint, image: CGImage, in context: CGContext) {
        let pixelCount = 15
        let diameter: CGFloat = 120
        let cell = diameter / CGFloat(pixelCount)
        let pixel = CaptureGeometry.pixel(at: point, viewSize: bounds.size, imageSize: imageSize)
        let half = pixelCount / 2
        let source = CGRect(x: pixel.x - half, y: pixel.y - half, width: pixelCount, height: pixelCount)

        var frame = CGRect(x: point.x + 24, y: point.y - 24 - diameter, width: diameter, height: diameter)
        if frame.maxX > bounds.width { frame.origin.x = point.x - 24 - diameter }
        if frame.minY < 30 { frame.origin.y = point.y + 24 }

        context.saveGState()
        context.addEllipse(in: frame)
        context.clip()
        context.setFillColor(NSColor.black.cgColor)
        context.fill(frame)
        if let crop = image.cropping(to: source) {
            // `cropping` clips at the image edge. Place the crop so the cursor pixel stays in the center.
            let dx = CGFloat(max(0, -source.minX)) * cell
            let dy = CGFloat(max(0, -source.minY)) * cell
            let drawRect = CGRect(
                x: frame.minX + dx,
                y: frame.maxY - dy - CGFloat(crop.height) * cell,
                width: CGFloat(crop.width) * cell,
                height: CGFloat(crop.height) * cell
            )
            context.interpolationQuality = .none
            context.draw(crop, in: drawRect)
        }
        let center = CGRect(x: frame.midX - cell / 2, y: frame.midY - cell / 2, width: cell, height: cell)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.stroke(center)
        context.restoreGState()

        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: frame.insetBy(dx: 1, dy: 1))

        let label = "\(pixel.x), \(pixel.y)"
        let size = Self.pillSize(label)
        drawPill(label, at: CGPoint(x: frame.midX - size.width / 2, y: frame.minY - size.height - 4))
    }

    private static let pillAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    private static func pillSize(_ text: String) -> CGSize {
        let size = (text as NSString).size(withAttributes: pillAttributes)
        return CGSize(width: size.width + 12, height: size.height + 6)
    }

    private func drawPill(_ text: String, at origin: CGPoint) {
        let size = Self.pillSize(text)
        let rect = CGRect(origin: origin, size: size)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: CGPoint(x: rect.minX + 6, y: rect.minY + 3), withAttributes: Self.pillAttributes)
    }
}
