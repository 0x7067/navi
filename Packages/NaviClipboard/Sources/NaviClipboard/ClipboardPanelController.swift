import AppKit
import NaviCore
import SwiftUI

/// A borderless panel that takes key focus without making Navi the active app.
/// The app you were typing in stays active, so Command-V lands there after the panel closes.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows and hides the history panel at the mouse, sizes it to fit, shows the preview card,
/// and handles keyboard keys.
@MainActor
final class ClipboardPanelController {
    private let model: ClipboardModel
    private let onChoose: (CaptureItem) -> Void
    private var panel: KeyPanel?
    private var previewPanel: NSPanel?
    private var previewTask: Task<Void, Never>?
    private var observingHeight = false
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    /// The panel's top-left corner. The panel grows and shrinks downward from here.
    private var topLeft: CGPoint = .zero
    private var screenFrame: CGRect = .zero

    init(model: ClipboardModel, onChoose: @escaping (CaptureItem) -> Void) {
        self.model = model
        self.onChoose = onChoose
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        let interval = HistorySignpost.signposter.beginInterval("PanelShow")
        let panel = panel ?? makePanel()
        self.panel = panel

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        screenFrame = screen?.visibleFrame ?? .zero
        topLeft = mouse

        model.reset()
        model.maxListHeight = max(screenFrame.height - Metrics.headerHeight - Metrics.footerHeight - 40, 200)
        model.onSelectionChange = { [weak self] in self?.schedulePreview() }

        // The list view is built once and kept: building it is most of the cost of an open.
        if !(panel.contentView is NSVisualEffectView) {
            let host = NSHostingView(rootView: ClipboardListView(
                model: model,
                onChoose: { [weak self] item in self?.choose(item) },
                onQuit: { NSApp.terminate(nil) }
            ))
            let container = Self.menuBackground(cornerRadius: 10)
            host.frame = container.bounds
            host.autoresizingMask = [.width, .height]
            container.addSubview(host)
            panel.contentView = container
        }

        applyHeight()
        observeHeight()
        panel.makeKeyAndOrderFront(nil)
        HistorySignpost.signposter.endInterval("PanelShow", interval)
        panel.invalidateShadow()
        installKeyMonitor()
        schedulePreview()
    }

    func hide() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        model.onSelectionChange = nil
        previewTask?.cancel()
        previewPanel?.orderOut(nil)
        panel?.orderOut(nil)
    }

    private func choose(_ item: CaptureItem) {
        hide()
        onChoose(item)
    }

    // MARK: Size and place

    private func applyHeight() {
        guard let panel else { return }
        let size = CGSize(width: Metrics.width, height: model.contentHeight)
        var origin = CGPoint(x: topLeft.x, y: topLeft.y - size.height)
        origin.x = min(max(origin.x, screenFrame.minX), screenFrame.maxX - size.width)
        origin.y = min(max(origin.y, screenFrame.minY), screenFrame.maxY - size.height)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.invalidateShadow()
    }

    /// Resizes the panel each time the content height changes (typing filters the list).
    private func observeHeight() {
        // One observer at a time: the panel is shown many times and each show asks for one.
        guard !observingHeight else { return }
        observingHeight = true
        withObservationTracking {
            _ = model.contentHeight
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observingHeight = false
                guard self.isVisible else { return }
                self.applyHeight()
                self.observeHeight()
            }
        }
    }

    // MARK: Preview card

    private func schedulePreview() {
        previewTask?.cancel()
        previewPanel?.orderOut(nil)
        previewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.showPreview()
        }
    }

    private func showPreview() {
        guard let panel, panel.isVisible, let item = model.selectedItem else { return }
        let preview = previewPanel ?? makePreviewPanel()
        previewPanel = preview

        let host = NSHostingView(rootView: ClipboardPreview(
            item: item,
            image: item.fileName == nil ? nil : model.image(for: item)
        ))
        let size = host.fittingSize
        let container = Self.menuBackground(cornerRadius: 12, material: .popover)
        container.frame = CGRect(origin: .zero, size: size)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        preview.contentView = container

        let rowMidY = panel.frame.maxY - (model.selectedRowMidY ?? 60)
        var x = panel.frame.minX - size.width - 8
        if x < screenFrame.minX { x = panel.frame.maxX + 8 }
        var y = rowMidY - size.height / 2
        y = min(max(y, screenFrame.minY), screenFrame.maxY - size.height)
        preview.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: true)
        preview.orderFront(nil)
        preview.invalidateShadow()
    }

    // MARK: Windows

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(
            contentRect: CGRect(x: 0, y: 0, width: Metrics.width, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        Self.style(panel)
        panel.level = .popUpMenu
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        return panel
    }

    private func makePreviewPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        Self.style(panel)
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        return panel
    }

    private static func style(_ panel: NSPanel) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    /// The blurred menu background with rounded corners.
    private static func menuBackground(cornerRadius: CGFloat, material: NSVisualEffectView.Material = .menu) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        let edge = cornerRadius * 2 + 1
        let mask = NSImage(size: CGSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        mask.resizingMode = .stretch
        view.maskImage = mask
        return view
    }

    // MARK: Keys

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }
    }

    /// Returns true when the key was used here and must not reach the text field.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch Int(event.keyCode) {
        case 53: // Esc
            hide()
            return true
        case 36, 76: // Return, Enter
            if let item = model.selectedItem { choose(item) }
            return true
        case 125: // Down
            model.move(by: 1)
            return true
        case 126: // Up
            model.move(by: -1)
            return true
        case 35 where flags == .option: // Option-P
            model.togglePinSelected()
            return true
        case 51 where flags == .option: // Option-Delete
            model.deleteSelected()
            return true
        case 51 where flags == [.option, .command]: // Option-Command-Delete
            model.clear()
            return true
        case 12 where flags == .command: // Command-Q
            NSApp.terminate(nil)
            return true
        default:
            break
        }
        if flags == .command, let digit = event.charactersIgnoringModifiers.flatMap(Int.init), (1...9).contains(digit) {
            if let item = model.item(at: digit - 1) { choose(item) }
            return true
        }
        return false
    }
}
