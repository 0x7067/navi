import AppKit
import Carbon.HIToolbox
import NaviCore

/// Puts an item on the pasteboard and presses Command-V in the front app.
@MainActor
enum Paster {
    /// Writes the item to the pasteboard. Returns the new pasteboard change count.
    static func write(_ item: CaptureItem, inbox: Inbox, to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        if let url = inbox.fileURL(for: item), let image = NSImage(contentsOf: url) {
            pasteboard.writeObjects([image])
        } else if let text = item.text {
            pasteboard.setString(text, forType: .string)
        }
        return pasteboard.changeCount
    }

    /// Sending a key press to another app needs the Accessibility permission.
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Shows the macOS prompt that opens System Settings > Privacy & Security > Accessibility.
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func pressCommandV() {
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
