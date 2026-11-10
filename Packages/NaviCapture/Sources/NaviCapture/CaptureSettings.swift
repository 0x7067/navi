import Foundation
import Observation

/// Capture settings, kept in `UserDefaults`.
@MainActor
@Observable
public final class CaptureSettings {
    @ObservationIgnored private let defaults: UserDefaults

    /// Leave Finder's desktop icons out of every capture. The real desktop does not change.
    public var hideDesktopIcons: Bool {
        didSet { defaults.set(hideDesktopIcons, forKey: Keys.hideDesktopIcons) }
    }

    /// Where Save puts files. Default: the Desktop, like macOS and CleanShot X.
    public var saveFolder: URL {
        didSet { defaults.set(saveFolder.path, forKey: Keys.saveFolder) }
    }

    /// Put every screenshot on the clipboard as soon as it is taken, and again after markup. Default: on.
    public var copyToClipboard: Bool {
        didSet { defaults.set(copyToClipboard, forKey: Keys.copyToClipboard) }
    }

    /// After an area shot, stay on the frozen screen and mark up the area in place. Return copies
    /// it to the clipboard and adds it to the history; no corner card. Default: off.
    public var editAfterCapture: Bool {
        didSet { defaults.set(editAfterCapture, forKey: Keys.editAfterCapture) }
    }

    /// Seconds before a corner card closes on its own. 0 means never.
    public var autoCloseSeconds: Double {
        didSet { defaults.set(autoCloseSeconds, forKey: Keys.autoCloseSeconds) }
    }

    /// Navi owns `⇧⌘3` and `⇧⌘4` and turns the macOS ones off while it runs. Nil until the user picks.
    public var useNaviScreenshotKeys: Bool? {
        didSet { defaults.set(useNaviScreenshotKeys, forKey: Keys.useNaviScreenshotKeys) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hideDesktopIcons = defaults.bool(forKey: Keys.hideDesktopIcons)
        saveFolder = defaults.string(forKey: Keys.saveFolder).map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? URL.desktopDirectory
        copyToClipboard = defaults.object(forKey: Keys.copyToClipboard) as? Bool ?? true
        editAfterCapture = defaults.bool(forKey: Keys.editAfterCapture)
        autoCloseSeconds = defaults.double(forKey: Keys.autoCloseSeconds)
        useNaviScreenshotKeys = defaults.object(forKey: Keys.useNaviScreenshotKeys) as? Bool
    }

    private enum Keys {
        static let hideDesktopIcons = "capture.hideDesktopIcons"
        static let saveFolder = "capture.saveFolder"
        static let copyToClipboard = "capture.copyToClipboard"
        static let editAfterCapture = "capture.editAfterCapture"
        static let autoCloseSeconds = "capture.autoCloseSeconds"
        static let useNaviScreenshotKeys = "capture.useNaviScreenshotKeys"
    }
}
