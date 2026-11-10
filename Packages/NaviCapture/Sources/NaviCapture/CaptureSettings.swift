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

    /// Navi's own save folder. Nil follows the macOS screenshot folder, then the Desktop.
    public var saveFolderOverride: URL? {
        didSet {
            if let saveFolderOverride {
                defaults.set(saveFolderOverride.path, forKey: Keys.saveFolder)
            } else {
                defaults.removeObject(forKey: Keys.saveFolder)
            }
        }
    }

    /// Where Save puts files: the override if set, else the macOS screenshot folder, else the Desktop.
    public var saveFolder: URL {
        get {
            SaveFolder.resolve(
                override: saveFolderOverride,
                systemLocation: SaveFolder.systemLocation(),
                home: FileManager.default.homeDirectoryForCurrentUser
            ) { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }
        }
        set { saveFolderOverride = newValue }
    }

    /// Put every screenshot on the clipboard as soon as it is taken, and again after markup. Default: on.
    public var copyToClipboard: Bool {
        didSet { defaults.set(copyToClipboard, forKey: Keys.copyToClipboard) }
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
        saveFolderOverride = defaults.string(forKey: Keys.saveFolder).map { URL(filePath: $0, directoryHint: .isDirectory) }
        copyToClipboard = defaults.object(forKey: Keys.copyToClipboard) as? Bool ?? true
        autoCloseSeconds = defaults.double(forKey: Keys.autoCloseSeconds)
        useNaviScreenshotKeys = defaults.object(forKey: Keys.useNaviScreenshotKeys) as? Bool
    }

    private enum Keys {
        static let hideDesktopIcons = "capture.hideDesktopIcons"
        static let saveFolder = "capture.saveFolder"
        static let copyToClipboard = "capture.copyToClipboard"
        static let autoCloseSeconds = "capture.autoCloseSeconds"
        static let useNaviScreenshotKeys = "capture.useNaviScreenshotKeys"
    }
}
