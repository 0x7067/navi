import Foundation
import os

/// Lends the fn (Globe) key to Navi while it runs.
///
/// macOS can act on fn: show the emoji picker, start Apple dictation, or change the input source. That
/// setting is `AppleFnUsageType` in the `com.apple.HIToolbox` preferences. `takeOver()` sets it to
/// "Do Nothing" and keeps a backup of the old value. `giveBack()` puts the exact old value back. If
/// the key had no value before (the macOS default), `giveBack()` removes the key again.
///
/// If Navi crashes, the backup stays. The next `takeOver()` keeps the first backup, and the next
/// `giveBack()` restores from it.
@MainActor
public enum SystemFnKey {
    private static let domain = "com.apple.HIToolbox" as CFString
    private static let key = "AppleFnUsageType" as CFString
    private static let backupKey = "dictation.fnUsageBackup"
    private static let logger = Logger(subsystem: "com.donovanhiland.navi", category: "SystemFnKey")

    /// True when Navi holds the fn key (a backup exists).
    public static var isTakenOver: Bool { UserDefaults.standard.dictionary(forKey: backupKey) != nil }

    /// Sets the fn key action to "Do Nothing". Keeps the first backup if one already exists.
    public static func takeOver() {
        let existing = UserDefaults.standard.dictionary(forKey: backupKey).flatMap(Backup.init(storage:))
        let (value, backup) = FnUsage.borrowing(current: read(), existingBackup: existing)
        if existing == nil { UserDefaults.standard.set(backup.storage, forKey: backupKey) }
        write(value)
    }

    /// Puts the fn key action back as it was before `takeOver()`.
    public static func giveBack() {
        guard let stored = UserDefaults.standard.dictionary(forKey: backupKey), let backup = Backup(storage: stored) else {
            UserDefaults.standard.removeObject(forKey: backupKey)
            return
        }
        write(FnUsage.restoring(backup))
        UserDefaults.standard.removeObject(forKey: backupKey)
    }

    // MARK: Pure logic

    typealias Backup = FnUsage.Backup

    // MARK: System

    private static func read() -> Int? {
        CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Int
    }

    /// Writes the value. `nil` removes the key.
    private static func write(_ value: Int?) {
        CFPreferencesSetValue(key, value.map { $0 as CFNumber }, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        if !CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) {
            logger.error("Could not save the fn key setting")
        }
        applyNow()
    }

    /// Makes macOS read the new setting now, without a logout.
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
            logger.error("Could not apply the fn key setting: \(error.localizedDescription)")
        }
    }
}

/// Pure logic for borrowing the fn key setting. Kept apart from the system calls, so tests can reach it.
enum FnUsage {
    /// `AppleFnUsageType` value for "Do Nothing". Other values: 1 change input source,
    /// 2 show emoji and symbols, 3 start dictation.
    static let doNothing = 0

    /// How the setting was before Navi changed it. `previous == nil` means the key had no value.
    struct Backup: Equatable {
        var previous: Int?

        init(previous: Int?) { self.previous = previous }

        /// Property-list form for `UserDefaults`. An empty dictionary means "no value".
        var storage: [String: Any] { previous.map { ["value": $0] } ?? [:] }

        init?(storage: [String: Any]) {
            if let value = storage["value"] as? Int {
                previous = value
            } else if storage.isEmpty {
                previous = nil
            } else {
                return nil
            }
        }
    }

    /// The value to write now, and the backup to keep. An existing backup wins, so a crash
    /// (value already "Do Nothing") does not overwrite the true old value.
    static func borrowing(current: Int?, existingBackup: Backup?) -> (value: Int, backup: Backup) {
        (doNothing, existingBackup ?? Backup(previous: current))
    }

    /// The value to write to put things back. `nil` means remove the key.
    static func restoring(_ backup: Backup) -> Int? {
        backup.previous
    }
}
