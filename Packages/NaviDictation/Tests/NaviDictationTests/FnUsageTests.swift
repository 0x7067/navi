import Testing
@testable import NaviDictation

@Suite("FnUsage")
struct FnUsageTests {
    @Test("borrowing sets Do Nothing and backs up the old value")
    func borrowsAndBacksUp() {
        let result = FnUsage.borrowing(current: 2, existingBackup: nil)
        #expect(result.value == FnUsage.doNothing)
        #expect(result.backup == FnUsage.Backup(previous: 2))
        #expect(FnUsage.restoring(result.backup) == 2)
    }

    @Test("a missing value is backed up as missing and restored by removing the key")
    func missingValue() {
        let result = FnUsage.borrowing(current: nil, existingBackup: nil)
        #expect(result.value == FnUsage.doNothing)
        #expect(result.backup == FnUsage.Backup(previous: nil))
        #expect(FnUsage.restoring(result.backup) == nil)
    }

    @Test("an existing backup wins, so a second borrow after a crash keeps the true old value")
    func keepsFirstBackup() {
        let first = FnUsage.Backup(previous: 3)
        let result = FnUsage.borrowing(current: FnUsage.doNothing, existingBackup: first)
        #expect(result.backup == first)
        #expect(FnUsage.restoring(result.backup) == 3)
    }

    @Test("a backup of Do Nothing itself restores to Do Nothing")
    func backupOfDoNothing() {
        let result = FnUsage.borrowing(current: 0, existingBackup: nil)
        #expect(FnUsage.restoring(result.backup) == 0)
    }

    @Test("backup survives a round trip through its property-list form")
    func storageRoundTrip() {
        for previous in [nil, 0, 1, 2, 3] as [Int?] {
            let backup = FnUsage.Backup(previous: previous)
            #expect(FnUsage.Backup(storage: backup.storage) == backup)
        }
        #expect(FnUsage.Backup(storage: ["junk": "x"]) == nil)
    }
}
