import AppKit
import Carbon.HIToolbox
import NaviCore

/// Types text into the front app. It puts the text on the pasteboard, presses ⌘V, and then puts the
/// old pasteboard contents back. Pressing keys in another app needs the Accessibility permission.
@MainActor
enum TextInserter {
    /// How long the pasted text stays on the pasteboard before the old contents return.
    static let restoreDelay: Duration = .milliseconds(600)

    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private struct SavedItem {
        let entries: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    static func insert(_ text: String, pasteboard: NSPasteboard = .general) async {
        let saved = save(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Navi's clipboard watcher skips this. Other clipboard managers skip the "transient" mark.
        pasteboard.setData(Data(), forType: NaviPasteboard.ownType)
        pasteboard.setData(Data(), forType: transientType)
        let ourChangeCount = pasteboard.changeCount

        // Give the pasteboard a moment to settle before the paste.
        try? await Task.sleep(for: .milliseconds(30))
        pressCommandV()
        try? await Task.sleep(for: restoreDelay)

        // If the user copied something else in the meantime, leave it alone.
        guard pasteboard.changeCount == ourChangeCount else { return }
        restore(saved, to: pasteboard)
    }

    private static func save(_ pasteboard: NSPasteboard) -> [SavedItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            SavedItem(entries: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    private static func restore(_ saved: [SavedItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !saved.isEmpty else { return }
        let items = saved.map { saved -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for entry in saved.entries { item.setData(entry.data, forType: entry.type) }
            return item
        }
        pasteboard.writeObjects(items)
    }

    private static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
