import AppKit
import NaviCore

/// Clipboard history: saves every copy to the Inbox and shows a keyboard-only picker that pastes.
@MainActor
public final class ClipboardFeature {
    private let inbox: Inbox
    private let watcher: ClipboardWatcher
    private let model: ClipboardModel
    private lazy var panel = ClipboardPanelController(model: model) { [weak self] item in
        self?.paste(item)
    }

    public init(inbox: Inbox) {
        self.inbox = inbox
        watcher = ClipboardWatcher(inbox: inbox)
        model = ClipboardModel(inbox: inbox)
    }

    public func start() {
        watcher.start()
    }

    public func showPanel() {
        if !panel.isVisible { panel.show() }
    }

    public func togglePanel() {
        if panel.isVisible { panel.hide() } else { panel.show() }
    }

    public static var hasAccessibility: Bool { Paster.hasAccessibility }

    public static func requestAccessibility() { Paster.requestAccessibility() }

    /// Copies the item and pastes it into the front app. Without Accessibility, it only copies.
    private func paste(_ item: CaptureItem) {
        let changeCount = Paster.write(item, inbox: inbox, to: .general)
        watcher.markOwnChange(changeCount)
        inbox.touch(item.id)
        guard Paster.hasAccessibility else {
            Paster.requestAccessibility()
            return
        }
        Task { @MainActor in
            // Give the panel time to close so the key press goes to the app underneath.
            try? await Task.sleep(for: .milliseconds(50))
            Paster.pressCommandV()
        }
    }
}
