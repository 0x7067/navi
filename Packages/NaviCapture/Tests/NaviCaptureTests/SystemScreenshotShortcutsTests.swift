import Foundation
import Testing

@testable import NaviCapture

@MainActor
@Suite struct SystemScreenshotShortcutsTests {
    @Test func disablingAMissingEntryAddsADisabledDefaultAndBacksUpNothing() throws {
        let (hotKeys, backup) = SystemScreenshotShortcuts.disabling(["28"], in: ["15": ["enabled": false]])
        let entry = try #require(hotKeys["28"] as? [String: Any])
        #expect(entry["enabled"] as? Bool == false)
        #expect(entry["value"] != nil)
        #expect((backup["28"] as? [String: Any])?.isEmpty == true)
        #expect(hotKeys["15"] != nil)
    }

    @Test func disablingAnExistingEntryKeepsItsValue() throws {
        let old: [String: Any] = ["enabled": true, "value": ["parameters": [1, 2, 3], "type": "standard"]]
        let (hotKeys, backup) = SystemScreenshotShortcuts.disabling(["30"], in: ["30": old])
        let entry = try #require(hotKeys["30"] as? [String: Any])
        #expect(entry["enabled"] as? Bool == false)
        #expect((entry["value"] as? [String: Any])?["parameters"] as? [Int] == [1, 2, 3])
        #expect((backup["30"] as? [String: Any])?["enabled"] as? Bool == true)
    }

    @Test func restoringPutsBackTheOldStateExactly() {
        let original: [String: Any] = ["30": ["enabled": false], "15": ["enabled": false]]
        let (changed, backup) = SystemScreenshotShortcuts.disabling(["28", "30"], in: original)
        let restored = SystemScreenshotShortcuts.restoring(backup, in: changed)
        #expect(restored["28"] == nil)
        #expect((restored["30"] as? [String: Any])?["enabled"] as? Bool == false)
        #expect(restored["15"] != nil)
        #expect(restored.count == original.count)
    }

    @Test func mergingKeepsOldEntriesAndAddsNewOnes() {
        let old: [String: Any] = ["28": [String: Any]()]
        let fresh: [String: Any] = ["28": ["enabled": false], "184": ["enabled": true]]
        let merged = SystemScreenshotShortcuts.merging(old: old, fresh: fresh)
        #expect((merged["28"] as? [String: Any])?.isEmpty == true)
        #expect((merged["184"] as? [String: Any])?["enabled"] as? Bool == true)
    }
}
