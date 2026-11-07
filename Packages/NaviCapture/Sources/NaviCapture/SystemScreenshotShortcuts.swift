import Foundation
import os

/// Lends macOS's `⇧⌘3`, `⇧⌘4`, and `⇧⌘5` screenshot shortcuts to Navi while it runs.
///
/// `takeOver()` turns the macOS shortcuts off and keeps a backup of how they were.
/// `giveBack()` puts them back exactly as they were. The app calls `giveBack()` when it quits, so the
/// macOS shortcuts work again once Navi is quit or deleted. If Navi crashes, the backup stays, and the
/// next launch or quit restores from it.
///
/// The shortcuts live in the `com.apple.symbolichotkeys` preferences, under `AppleSymbolicHotKeys`.
@MainActor
public enum SystemScreenshotShortcuts {
    /// Symbolic hot key IDs. 28: save the screen as a file (`⇧⌘3`). 30: save an area as a file (`⇧⌘4`).
    /// 184: the screenshot and recording toolbar (`⇧⌘5`).
    /// Each one maps to its default entry, used when the preferences have no entry for it.
    static let defaults: [String: [String: Any]] = [
        "28": entry(enabled: true, parameters: [51, 20, 1_179_648]),
        "30": entry(enabled: true, parameters: [52, 21, 1_179_648]),
        "184": entry(enabled: true, parameters: [53, 23, 1_179_648]),
    ]

    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let key = "AppleSymbolicHotKeys" as CFString
    private static let backupKey = "capture.systemShortcutsBackup"
    private static let logger = Logger(subsystem: "com.donovanhiland.navi", category: "SystemShortcuts")

    /// True when Navi holds the shortcuts (a backup exists).
    public static var isTakenOver: Bool { UserDefaults.standard.dictionary(forKey: backupKey) != nil }

    /// Turns the macOS shortcuts off. An existing backup (after a crash) keeps its old entries.
    public static func takeOver() {
        let (updated, fresh) = disabling(Array(defaults.keys), in: read())
        // Keep old backup entries (they hold the state before Navi). Add entries for keys new to the backup.
        let old = UserDefaults.standard.dictionary(forKey: backupKey) ?? [:]
        UserDefaults.standard.set(merging(old: old, fresh: fresh), forKey: backupKey)
        write(updated)
    }

    /// Puts the macOS shortcuts back as they were before `takeOver()`.
    public static func giveBack() {
        guard let backup = UserDefaults.standard.dictionary(forKey: backupKey) else { return }
        write(restoring(backup, in: read()))
        UserDefaults.standard.removeObject(forKey: backupKey)
    }

    // MARK: Pure logic

    /// Returns the hot keys with `ids` turned off, and a backup of the old entries.
    /// In the backup, an ID with an empty dictionary means "there was no entry".
    static func disabling(_ ids: [String], in hotKeys: [String: Any]) -> (hotKeys: [String: Any], backup: [String: Any]) {
        var hotKeys = hotKeys
        var backup: [String: Any] = [:]
        for id in ids {
            let old = hotKeys[id] as? [String: Any]
            backup[id] = old ?? [String: Any]()
            var new = old ?? defaults[id] ?? [:]
            new["enabled"] = false
            hotKeys[id] = new
        }
        return (hotKeys, backup)
    }

    /// The backup to keep: every old entry, plus fresh entries for IDs the old backup lacks.
    static func merging(old: [String: Any], fresh: [String: Any]) -> [String: Any] {
        old.merging(fresh) { kept, _ in kept }
    }

    /// Returns the hot keys with each backed-up entry put back. Empty backup entries are removed,
    /// so macOS uses its default (on).
    static func restoring(_ backup: [String: Any], in hotKeys: [String: Any]) -> [String: Any] {
        var hotKeys = hotKeys
        for (id, old) in backup {
            if let old = old as? [String: Any], !old.isEmpty {
                hotKeys[id] = old
            } else {
                hotKeys[id] = nil
            }
        }
        return hotKeys
    }

    private static func entry(enabled: Bool, parameters: [Int]) -> [String: Any] {
        ["enabled": enabled, "value": ["parameters": parameters, "type": "standard"]]
    }

    // MARK: System

    private static func read() -> [String: Any] {
        CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any] ?? [:]
    }

    private static func write(_ hotKeys: [String: Any]) {
        CFPreferencesSetValue(key, hotKeys as CFDictionary, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        applyNow()
    }

    /// Makes macOS read the new shortcuts now, without a logout.
    private static func applyNow() {
        let process = Process()
        process.executableURL = URL(
            filePath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
        )
        process.arguments = ["-u"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("Could not apply shortcut settings: \(error.localizedDescription)")
        }
    }
}
