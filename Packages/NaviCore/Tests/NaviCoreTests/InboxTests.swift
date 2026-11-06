import Foundation
import Testing
@testable import NaviCore

@MainActor
struct InboxTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "NaviTests-\(UUID().uuidString)")
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func newestTextComesFirst() {
        let inbox = Inbox(directory: directory)
        inbox.add(text: "one", now: start)
        inbox.add(text: "two", now: start + 1)
        #expect(inbox.items.map(\.text) == ["two", "one"])
    }

    @Test func blankTextIsIgnored() {
        let inbox = Inbox(directory: directory)
        #expect(inbox.add(text: "  \n ") == nil)
        #expect(inbox.items.isEmpty)
    }

    @Test func duplicateTextMovesToTopWithoutCopy() {
        let inbox = Inbox(directory: directory)
        let first = inbox.add(text: "one", now: start)
        inbox.add(text: "two", now: start + 1)
        let again = inbox.add(text: "one", now: start + 2)
        #expect(again?.id == first?.id)
        #expect(inbox.items.map(\.text) == ["one", "two"])
        #expect(inbox.items[0].copyCount == 2)
        #expect(inbox.items[0].createdAt == start)
        #expect(inbox.items[0].lastUsedAt == start + 2)
    }

    @Test func pasteMovesItemToTopWithoutCountingACopy() throws {
        let inbox = Inbox(directory: directory)
        let first = try #require(inbox.add(text: "one", now: start))
        inbox.add(text: "two", now: start + 1)
        inbox.touch(first.id, now: start + 2)
        #expect(inbox.items.map(\.text) == ["one", "two"])
        #expect(inbox.items[0].copyCount == 1)
    }

    @Test func readsHistoryFromBeforeCopyCounts() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = """
        [{"id":"\(UUID().uuidString)","kind":"text","createdAt":0,"pinned":false,"text":"old","contentHash":"x"}]
        """
        try Data(old.utf8).write(to: directory.appending(path: "history.json"))
        let inbox = Inbox(directory: directory)
        #expect(inbox.items.first?.copyCount == 1)
        #expect(inbox.items.first?.lastUsedAt == inbox.items.first?.createdAt)
    }

    @Test func pinnedItemsStayOnTopAndSurviveTheLimit() throws {
        let inbox = Inbox(directory: directory, limit: 2)
        let pinned = try #require(inbox.add(text: "keep", now: start))
        inbox.togglePin(pinned.id)
        inbox.add(text: "a", now: start + 1)
        inbox.add(text: "b", now: start + 2)
        inbox.add(text: "c", now: start + 3)
        #expect(inbox.items.map(\.text) == ["keep", "c", "b"])
    }

    @Test func searchIgnoresCase() {
        let inbox = Inbox(directory: directory)
        inbox.add(text: "Hello World", now: start)
        inbox.add(text: "other", now: start + 1)
        #expect(inbox.search("hello").map(\.text) == ["Hello World"])
        #expect(inbox.search("").count == 2)
    }

    @Test func historySurvivesRestart() {
        let inbox = Inbox(directory: directory)
        inbox.add(text: "saved", now: start)
        let reopened = Inbox(directory: directory)
        #expect(reopened.items.map(\.text) == ["saved"])
    }

    @Test func removingAnImageDeletesItsFile() throws {
        let inbox = Inbox(directory: directory)
        let item = try #require(inbox.add(fileData: Data([1, 2, 3]), fileExtension: "png", kind: .image))
        let url = try #require(inbox.fileURL(for: item))
        #expect(FileManager.default.fileExists(atPath: url.path))
        inbox.remove(item.id)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(inbox.items.isEmpty)
    }

    @Test func clearKeepsPinnedItems() throws {
        let inbox = Inbox(directory: directory)
        let pinned = try #require(inbox.add(text: "keep", now: start))
        inbox.togglePin(pinned.id)
        inbox.add(text: "drop", now: start + 1)
        inbox.clearUnpinned()
        #expect(inbox.items.map(\.text) == ["keep"])
    }
}
