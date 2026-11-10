import AppKit
import Carbon.HIToolbox
import NaviCore
import SwiftUI

/// What happened when a new History shortcut was tried.
enum HistoryShortcutChange: Equatable {
    case applied
    case invalid(KeyComboError)
    /// macOS or another app owns the combo, so Carbon refused to register it.
    case refused

    /// The line the recorder shows under its prompt. Nil when the change was applied.
    var message: String? {
        switch self {
        case .applied: nil
        case .invalid(.needsModifier), .invalid(.shiftOnly): "Use ⌘, ⌥ or ⌃ in the shortcut."
        case let .invalid(.inUse(name)): "Navi already uses this for \(name)."
        case .refused: "macOS or another app already uses this shortcut."
        }
    }
}

/// What the recorder panel shows.
@Observable
@MainActor
final class RecorderState {
    var current: KeyCombo = .defaultHistory
    var message: String?
}

/// The recorder panel: a prompt, the current shortcut, the last error, and Reset and Cancel.
private struct RecorderView: View {
    let state: RecorderState
    let onReset: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Press a new shortcut").font(.headline)
            Text("Current: \(state.current.display)").foregroundStyle(.secondary)
            Text(state.message ?? "")
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .frame(minHeight: 34)
            HStack {
                Button("Reset to \(KeyCombo.defaultHistory.display)", action: onReset)
                Button("Cancel", action: onCancel)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

/// Records a new History shortcut in a small floating panel. Navi's own shortcuts are off while it is open,
/// so the keys reach the panel. Escape, Cancel, or clicking away closes it without a change.
@MainActor
final class HistoryShortcutRecorder: NSObject, NSWindowDelegate {
    private let apply: (KeyCombo) -> HistoryShortcutChange
    private let onClose: () -> Void
    private let state = RecorderState()
    private var panel: NSPanel?
    private var monitor: Any?

    /// `apply` tries a combo and reports the result. `onClose` runs once when the panel closes.
    init(apply: @escaping (KeyCombo) -> HistoryShortcutChange, onClose: @escaping () -> Void) {
        self.apply = apply
        self.onClose = onClose
    }

    /// Opens the panel, or brings it forward when it is already open.
    func show(current: KeyCombo) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        state.current = current
        state.message = nil
        let view = RecorderView(
            state: state,
            onReset: { [weak self] in self?.attempt(.defaultHistory) },
            onCancel: { [weak self] in self?.finish() }
        )
        let hosting = NSHostingView(rootView: view)
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        panel.title = "Change History Shortcut"
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()
        self.panel = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        // The monitor swallows every key press while the panel is open, so Navi's menus and shortcuts stay quiet.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) ?? false } ? nil : event
        }
    }

    /// Returns true when the key was used, so the monitor swallows it.
    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == UInt16(kVK_Escape) {
            finish()
        } else {
            attempt(KeyCombo.from(keyCode: event.keyCode, cocoaFlags: event.modifierFlags))
        }
        return true
    }

    /// A valid, accepted combo closes the panel. Anything else keeps it open with the reason shown.
    private func attempt(_ combo: KeyCombo) {
        let change = apply(combo)
        if change == .applied {
            finish()
        } else {
            state.message = change.message
        }
    }

    /// Closes the panel and removes the monitor, then runs `onClose`. Safe to call more than once.
    private func finish() {
        guard let panel else { return }
        self.panel = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel.delegate = nil
        panel.close()
        onClose()
    }

    /// Clicking away cancels, so Navi's shortcuts never stay off.
    func windowDidResignKey(_ notification: Notification) {
        finish()
    }
}
