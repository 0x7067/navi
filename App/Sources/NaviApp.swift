import Carbon.HIToolbox
import NaviClipboard
import NaviCore
import SwiftUI
import os

@main
struct NaviApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Navi", systemImage: "sparkle") {
            Button("Open History (⇧⌘V)") { appDelegate.clipboard.togglePanel() }
            Divider()
            Button("Clear History") { appDelegate.inbox.clearUnpinned() }
            Button("Accessibility Permission…") { ClipboardFeature.requestAccessibility() }
            Divider()
            Button("Quit Navi") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let inbox = Inbox()
    lazy var clipboard = ClipboardFeature(inbox: inbox)
    private var historyHotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        clipboard.start()
        historyHotKey = HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.clipboard.togglePanel()
        }
        if historyHotKey == nil {
            Logger(subsystem: "com.donovanhiland.navi", category: "App")
                .error("Could not register ⇧⌘V. Another app may own it.")
        }
        if !ClipboardFeature.hasAccessibility {
            ClipboardFeature.requestAccessibility()
        }
    }

    /// Opening Navi again while it runs (Finder, Spotlight, `open`) shows the history.
    /// This helps when the menu bar icon is hidden behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        clipboard.showPanel()
        return false
    }
}
