import Carbon.HIToolbox
import NaviCapture
import NaviClipboard
import NaviCore
import NaviDictation
import NaviRecording
import Sparkle
import SwiftUI
import os

@main
struct NaviApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar icon and its menu are AppKit (`NaviMenu`), so a hot key can open the menu.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let inbox = Inbox()
    lazy var clipboard = ClipboardFeature(inbox: inbox)
    lazy var capture = CaptureFeature(inbox: inbox)
    let recording = RecordingFeature()
    /// Sparkle: checks the appcast on the GitHub Releases page once a day, and from the menu.
    /// Off in Debug builds, so a release never replaces the development copy (it has a different
    /// signature, and macOS would ask for every permission again).
    #if DEBUG
    let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    #else
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    #endif
    lazy var dictation = DictationFeature(inbox: inbox)
    private var historyHotKey: HotKey?
    private var menuHotKey: HotKey?
    private var extraHotKeys: [HotKey] = []
    private lazy var naviMenu = NaviMenu(app: self)
    private var screenshotHotKeys: [HotKey] = []
    private var signalSources: [any DispatchSourceSignal] = []
    private let logger = Logger(subsystem: "com.donovanhiland.navi", category: "App")

    func applicationDidFinishLaunching(_ notification: Notification) {
        clipboard.start()
        _ = naviMenu
        historyHotKey = register("⇧⌘V", keyCode: kVK_ANSI_V) { [weak self] in self?.clipboard.togglePanel() }
        extraHotKeys = [
            register("⌥⇧⌘T", keyCode: kVK_ANSI_T, modifiers: cmdKey | shiftKey | optionKey) { [weak self] in
                self?.capture.captureText()
            },
            register("⌥⇧⌘4", keyCode: kVK_ANSI_4, modifiers: cmdKey | shiftKey | optionKey) { [weak self] in
                self?.capture.captureScrolling()
            },
            register("⌥⇧⌘5", keyCode: kVK_ANSI_5, modifiers: cmdKey | shiftKey | optionKey) { [weak self] in
                guard let self else { return }
                recording.isRecording ? recording.stop() : capture.pickRecordingRegion()
            },
        ].compactMap(\.self)
        menuHotKey = register("⌥⇧⌘N", keyCode: kVK_ANSI_N, modifiers: cmdKey | shiftKey | optionKey) { [weak self] in
            self?.naviMenu.popUpAtMouse()
        }
        quitCleanlyOnSignals()
        wireRecording()
        dictation.onProblem = { CaptureFeature.showMessage($0) }
        if dictation.hasChosen {
            dictation.start()
            if dictation.isEnabled { dictation.borrowFnKey() } else { dictation.giveBackFnKey() }
        }
        switch capture.settings.useNaviScreenshotKeys {
        case true?: setUseNaviScreenshotKeys(true)
        case false?: SystemScreenshotShortcuts.giveBack() // Left over from a crash.
        case nil: askAboutScreenshotKeys()
        }
        if !dictation.hasChosen { askAboutTalkToType() }
        if !ClipboardFeature.hasAccessibility {
            ClipboardFeature.requestAccessibility()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Give macOS its keys back, so they work when Navi is quit or deleted.
        SystemScreenshotShortcuts.giveBack()
        dictation.stop()
        dictation.giveBackFnKey()
        recording.stop()
    }

    private func askAboutTalkToType() {
        let alert = NSAlert()
        alert.messageText = "Use fn for Talk to Type?"
        alert.informativeText = """
            Hold fn, talk, and let go: Navi types what you said. While Navi runs, a tap on fn does nothing \
            else (no emoji picker). Navi puts the fn key back when it quits. You can change this in the Navi menu.
            """
        alert.addButton(withTitle: "Use fn")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        let use = alert.runModal() == .alertFirstButtonReturn
        dictation.start()
        setTalkToType(use)
    }

    /// Talk to type: hold fn. On: the macOS fn key action is "Do Nothing" while Navi runs.
    func setTalkToType(_ on: Bool) {
        dictation.isEnabled = on
        if on {
            dictation.borrowFnKey()
            Task { _ = await DictationFeature.requestPermissions() }
        } else {
            dictation.giveBackFnKey()
        }
    }

    /// Connects screen recording to the capture overlay and the corner cards.
    private func wireRecording() {
        recording.onError = { CaptureFeature.showMessage($0.localizedDescription) }
        capture.videoTools = VideoTools(
            trim: { [recording] url in await recording.trim(url) },
            makeGIF: { url in try await RecordingFeature.makeGIF(from: url) }
        )
        capture.onRecordRequest = { [weak self] region in
            guard let self else { return }
            let target: RecordingRegion = switch region {
            case let .display(id): .display(id)
            case let .area(id, rect): .area(id, rect)
            case let .window(id): .window(id)
            }
            recording.showRecordBar(region: target) { [weak self] result in
                self?.capture.showRecording(
                    url: result.url, videoURL: result.videoURL, isGIF: result.isGIF, duration: result.duration
                )
            }
        }
    }

    /// Turns Navi's screenshot keys (⇧⌘3, ⇧⌘4, ⇧⌘5, ⌃⇧⌘3, ⌃⇧⌘4) on or off. On: the macOS screenshot keys are off while Navi runs.
    func setUseNaviScreenshotKeys(_ use: Bool) {
        capture.settings.useNaviScreenshotKeys = use
        for hotKey in screenshotHotKeys { hotKey.unregister() }
        screenshotHotKeys = []
        guard use else {
            SystemScreenshotShortcuts.giveBack()
            return
        }
        SystemScreenshotShortcuts.takeOver()
        screenshotHotKeys = [
            register("⇧⌘3", keyCode: kVK_ANSI_3) { [weak self] in self?.capture.captureFullscreen() },
            register("⇧⌘4", keyCode: kVK_ANSI_4) { [weak self] in self?.capture.captureArea() },
            register("⇧⌘5", keyCode: kVK_ANSI_5) { [weak self] in self?.capture.captureAllInOne() },
            register("⌃⇧⌘3", keyCode: kVK_ANSI_3, modifiers: cmdKey | shiftKey | controlKey) { [weak self] in
                self?.capture.captureFullscreenToClipboard()
            },
            register("⌃⇧⌘4", keyCode: kVK_ANSI_4, modifiers: cmdKey | shiftKey | controlKey) { [weak self] in
                self?.capture.captureAreaToClipboard()
            },
        ].compactMap(\.self)
    }

    private func askAboutScreenshotKeys() {
        let alert = NSAlert()
        alert.messageText = "Use Navi for the screenshot keys?"
        alert.informativeText = """
            While Navi runs, ⇧⌘3, ⇧⌘4, and ⇧⌘5 take screenshots with Navi, and ⌃⇧⌘3 and ⌃⇧⌘4 also copy them. Navi turns off the macOS screenshot \
            keys while it runs, and turns them back on when it quits. You can change this in the Navi menu.
            """
        alert.addButton(withTitle: "Use Navi")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        setUseNaviScreenshotKeys(alert.runModal() == .alertFirstButtonReturn)
    }

    /// `pkill` and `kill` send SIGTERM, which skips `applicationWillTerminate`. Quit the normal way instead.
    private func quitCleanlyOnSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    private func register(
        _ name: String, keyCode: Int, modifiers: Int = cmdKey | shiftKey, action: @escaping () -> Void
    ) -> HotKey? {
        guard let hotKey = HotKey(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers), action: action) else {
            logger.error("Could not register \(name, privacy: .public). Another app may own it.")
            return nil
        }
        return hotKey
    }

    /// Opening Navi again while it runs (Finder, Spotlight, `open`) shows the history.
    /// This helps when the menu bar icon is hidden behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        clipboard.showPanel()
        return false
    }
}
