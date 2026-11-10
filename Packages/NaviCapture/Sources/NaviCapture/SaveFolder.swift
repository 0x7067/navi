import Foundation

/// Picks the folder that Save writes to.
enum SaveFolder {
    /// The folder for saved captures. Precedence: Navi's own override, then the macOS
    /// screenshot folder when it exists, then the Desktop.
    /// - Parameters:
    ///   - override: Navi's `capture.saveFolder` setting. Nil when unset.
    ///   - systemLocation: The value of `defaults read com.apple.screencapture location`.
    ///   - home: The user's home folder, used for `~` and the Desktop fallback.
    ///   - isDirectory: Tells whether a URL is an existing folder.
    static func resolve(override: URL?, systemLocation: String?, home: URL, isDirectory: (URL) -> Bool) -> URL {
        if let override { return override }
        let desktop = home.appending(path: "Desktop", directoryHint: .isDirectory)
        guard let systemURL = systemURL(from: systemLocation, home: home), isDirectory(systemURL) else {
            return desktop
        }
        return systemURL
    }

    /// The macOS screenshot folder, read fresh on every call so a change applies without a relaunch.
    static func systemLocation() -> String? {
        let domain = "com.apple.screencapture" as CFString
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue("location" as CFString, domain) as? String
    }

    /// Turns the stored location into a URL. Relative paths are ignored, because a
    /// working directory means nothing for a screenshot folder.
    private static func systemURL(from location: String?, home: URL) -> URL? {
        guard let trimmed = location?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if trimmed == "~" {
            return home
        }
        if trimmed.hasPrefix("~/") {
            return home.appending(path: String(trimmed.dropFirst(2)), directoryHint: .isDirectory)
        }
        guard trimmed.hasPrefix("/") else { return nil }
        return URL(filePath: trimmed, directoryHint: .isDirectory)
    }
}
