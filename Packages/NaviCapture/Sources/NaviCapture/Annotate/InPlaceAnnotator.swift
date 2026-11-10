import AppKit
import Carbon.HIToolbox
import NaviCore
import SwiftUI
import os

/// Edit after capture. The captured area stays where it was on the frozen, dimmed screen, so it
/// still looks like a screenshot in progress, and it becomes the markup canvas. The toolbar floats
/// beside the area. No window, no title bar. Return copies the marked-up shot; Esc cancels.
@MainActor
final class InPlaceAnnotator {
    private static let logger = Logger(subsystem: "com.donovanhiland.navi", category: "Capture")
    private let model: AnnotateModel
    private let screen: NSScreen
    /// The area in display-local points with the origin at the top left.
    private let area: CGRect
    /// The frozen screen behind the area. Nil when it is missing: then the dim covers the live screen.
    private let backdrop: CGImage?
    private var window: InPlaceWindow?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    /// Return and Esc as Carbon hot keys until Navi is the active app. macOS may refuse
    /// `NSApp.activate()`, and then no key event reaches the window or the local monitor.
    private var fallbackKeys: [HotKey] = []
    private var colorPanelLevel: NSWindow.Level?
    /// Gets the result on Return or Copy, nil on Esc or Cancel. Runs once.
    private var onFinish: ((AnnotateEditor.Result?) -> Void)?

    init(
        captured: CapturedImage, backdrop: CGImage?, screen: NSScreen, area: CGRect,
        onFinish: @escaping (AnnotateEditor.Result?) -> Void
    ) {
        model = AnnotateModel(base: captured.image, scale: captured.scale)
        self.backdrop = backdrop
        self.screen = screen
        self.area = area
        self.onFinish = onFinish
    }

    func show() {
        let window = InPlaceWindow(screen: screen)
        let hosting = NSHostingView(rootView: InPlaceAnnotateView(
            model: model,
            backdrop: backdrop,
            area: area,
            onDone: { [weak self] in self?.finish(copying: true) },
            onCancel: { [weak self] in self?.finish(copying: false) }
        ))
        // The window is the size of the screen. Do not let SwiftUI resize it to fit the content.
        hosting.sizingOptions = []
        window.contentView = hosting
        self.window = window
        watchKeys()
        // The color panel floats at a low level. Lift it above the overlay while it is open.
        colorPanelLevel = NSColorPanel.shared.level
        NSColorPanel.shared.level = InPlaceWindow.overlayLevel + 1
        if !NSApp.isActive { registerFallbackKeys() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseFallbackKeys() }
        }
        // ⌘Tab or a click in another app would leave the dim up with capture locked. Cancel instead.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(copying: false) }
        }
    }

    private func finish(copying: Bool) {
        guard let onFinish else { return }
        self.onFinish = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        activeObserver = nil
        releaseFallbackKeys()
        if let colorPanelLevel { NSColorPanel.shared.level = colorPanelLevel }
        colorPanelLevel = nil
        window?.orderOut(nil)
        window = nil
        guard copying else {
            onFinish(nil)
            return
        }
        guard let flat = model.flatten() else {
            Self.logger.error("Could not flatten the marked-up capture")
            Toast.show("Could not copy the screenshot", on: screen)
            onFinish(nil)
            return
        }
        onFinish(AnnotateEditor.Result(flat: flat, base: model.base, document: model.document, pointSize: model.pointSize))
    }

    /// Return copies and Esc cancels, unless text is being typed or a crop is open: then they end
    /// that first. Every other markup key works as in the editor window.
    private func watchKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, let window = self.window, window.windowNumber == event.windowNumber else { return false }
                return self.handle(event)
            }
            return handled ? nil : event
        }
    }

    private func registerFallbackKeys() {
        let confirm: () -> Void = { [weak self] in self?.pressReturn() }
        fallbackKeys = [
            HotKey(keyCode: UInt32(kVK_Escape), modifiers: 0) { [weak self] in self?.pressEscape() },
            HotKey(keyCode: UInt32(kVK_Return), modifiers: 0, action: confirm),
            HotKey(keyCode: UInt32(kVK_ANSI_KeypadEnter), modifiers: 0, action: confirm),
        ].compactMap { $0 }
    }

    /// Once Navi is active, the local key monitor has the keys and other apps get theirs back.
    private func releaseFallbackKeys() {
        for key in fallbackKeys { key.unregister() }
        fallbackKeys = []
    }

    private func pressReturn() {
        if model.textEdit != nil { model.finishText() } else if model.cropRect != nil { model.applyCrop() } else { finish(copying: true) }
    }

    private func pressEscape() {
        if model.textEdit != nil { model.finishText() } else if model.cropRect != nil { model.cancelCrop() } else { finish(copying: false) }
    }

    private func handle(_ event: NSEvent) -> Bool {
        let code = event.keyCode
        let isReturn = code == AnnotateKeys.returnKey || code == AnnotateKeys.keypadEnter
        let plain = AnnotateKeys.modifiers(of: event).isEmpty
        if model.textEdit == nil, model.cropRect != nil, plain {
            if isReturn { model.applyCrop(); return true }
            if code == AnnotateKeys.escape { model.cancelCrop(); return true }
        }
        if model.textEdit == nil, plain {
            if isReturn { finish(copying: true); return true }
            if code == AnnotateKeys.escape { finish(copying: false); return true }
        }
        return AnnotateKeys.handle(event, model: model)
    }
}

/// A borderless window over one whole screen, above other apps.
private final class InPlaceWindow: NSWindow {
    /// Above the menu bar and Dock, but at menu level, so the toolbar's menus and popovers show
    /// above the overlay.
    static let overlayLevel = NSWindow.Level.popUpMenu

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = Self.overlayLevel
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The frozen screen, dimmed except the area, the canvas on the area, and the floating toolbar.
struct InPlaceAnnotateView: View {
    @Bindable var model: AnnotateModel
    let backdrop: CGImage?
    let area: CGRect
    let onDone: () -> Void
    let onCancel: () -> Void
    @State private var toolbarSize = CGSize(width: 900, height: 44)

    private static let dim = Color.black.opacity(0.35)
    private static let toolbarGap: CGFloat = 10
    private static let screenMargin: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            // Crop, rotate, and resize change the shot's size. The canvas grows or shrinks from
            // the area's top-left corner.
            let hole = CGRect(origin: area.origin, size: model.pointSize)
            let toolbarOrigin = CaptureGeometry.toolbarOrigin(
                below: hole, toolbar: toolbarSize, in: proxy.size, gap: Self.toolbarGap, margin: Self.screenMargin
            )
            ZStack(alignment: .topLeading) {
                if let backdrop {
                    Image(decorative: backdrop, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                dim(around: hole, in: proxy.size)
                AnnotateCanvas(model: model, layout: .actualSize)
                    .frame(width: hole.width, height: hole.height)
                    .offset(x: hole.minX, y: hole.minY)
                Rectangle()
                    .stroke(Color.white, lineWidth: 1)
                    .frame(width: hole.width + 1, height: hole.height + 1)
                    .offset(x: hole.minX - 0.5, y: hole.minY - 0.5)
                    .allowsHitTesting(false)
                toolbar
                    .offset(x: toolbarOrigin.x, y: toolbarOrigin.y)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
    }

    /// Clicks on the dim do nothing, so a stray click cannot lose the marks.
    private func dim(around hole: CGRect, in size: CGSize) -> some View {
        Rectangle()
            .fill(Self.dim)
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .frame(width: hole.width, height: hole.height)
                    .offset(x: hole.minX, y: hole.minY)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
        .onTapGesture {}
        .onHover { inside in if inside { NSCursor.arrow.set() } }
    }

    private var toolbar: some View {
        AnnotateToolbar(model: model, onDone: onDone, onCancel: onCancel, doneTitle: "Copy", doneModifiers: nil, showsDragThumbnail: false)
            .fixedSize()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { toolbarSize = $0 }
    }
}
