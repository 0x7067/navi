import Foundation
import Testing
@testable import NaviCore

struct HistoryDecodeTests {
    private func item(_ n: Int, text: String? = nil) -> CaptureItem {
        CaptureItem(
            id: UUID(), kind: CaptureKind.allCases[n % CaptureKind.allCases.count],
            createdAt: Date(timeIntervalSince1970: 1_000_000 + Double(n)),
            lastUsedAt: Date(timeIntervalSince1970: 2_000_000 + Double(n)), copyCount: n + 1, pinned: n % 2 == 0,
            text: text ?? "item \\ \"\(n)\" },{\"id\": \u{1F600} \n end", fileName: n % 3 == 0 ? "f\(n).png" : nil,
            sourceApp: "App \(n)", sourceBundleID: "com.example.\(n)", contentHash: "hash\(n)"
        )
    }

    @Test func everyFieldRoundTripsThroughTheOldEncoder() throws {
        let items = (0..<20).map { item($0) }
        let data = try JSONEncoder().encode(items)
        #expect(try CaptureItem.decodeHistory(from: data) == items)
    }

    @Test func bigFileDecodesInParallelToTheSameItems() throws {
        let filler = String(repeating: "the report \"quoted\" },{\"id\":1 ", count: 200)
        let items = (0..<400).map { item($0, text: filler + "\($0)") }
        let data = try JSONEncoder().encode(items)
        #expect(data.count > 512 * 1024)
        #expect(try CaptureItem.decodeHistory(from: data) == items)
        #expect(try JSONDecoder().decode([CaptureItem].self, from: data) == items)
    }

    @Test func prettyPrintedFileStillDecodes() throws {
        let items = (0..<10).map { item($0, text: String(repeating: "x", count: 100_000)) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(items)
        #expect(try CaptureItem.decodeHistory(from: data) == items)
    }

    @Test func missingOptionalFieldsStillDecode() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","kind":"text","createdAt":5,"pinned":false,"contentHash":"h"}]
        """
        let decoded = try CaptureItem.decodeHistory(from: Data(json.utf8))
        #expect(decoded.count == 1)
        #expect(decoded[0].lastUsedAt == decoded[0].createdAt)
        #expect(decoded[0].copyCount == 1)
        #expect(decoded[0].text == nil && decoded[0].fileName == nil)
        #expect(decoded[0].sourceApp == nil && decoded[0].sourceBundleID == nil)
    }

    @Test func corruptFileThrows() {
        #expect(throws: (any Error).self) { try CaptureItem.decodeHistory(from: Data("[{\"id\":".utf8)) }
    }

    @Test @MainActor func inboxLoadsAFileWrittenByTheOldEncoder() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "NaviTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let items = (0..<30).map { item($0) }
        try JSONEncoder().encode(items).write(to: directory.appending(path: "history.json"))
        let inbox = Inbox(directory: directory)
        #expect(Set(inbox.items.map(\.id)) == Set(items.map(\.id)))
        #expect(inbox.items.first(where: { $0.id == items[3].id }) == items[3])
    }
}
