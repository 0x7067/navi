import Foundation

/// What kind of capture an item holds. Every feature writes into the same Inbox.
public enum CaptureKind: String, Codable, Sendable, CaseIterable {
    case text
    case image
    case screenshot
    case recording
    case dictation
}

/// One entry in the shared history list.
public struct CaptureItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var kind: CaptureKind
    /// First time this content was captured.
    public var createdAt: Date
    /// Last time this content was copied or pasted. The history is sorted by this.
    public var lastUsedAt: Date
    /// How many times this content was copied.
    public var copyCount: Int
    public var pinned: Bool
    /// Text content, for text and dictation items.
    public var text: String?
    /// File name inside the Inbox files folder, for images, screenshots, and recordings.
    public var fileName: String?
    /// Name of the app that was in front when the item was captured.
    public var sourceApp: String?
    /// Bundle ID of that app, used to show its icon.
    public var sourceBundleID: String?
    /// SHA-256 of the content. Used to find duplicates.
    public var contentHash: String

    /// Creates an item from its stored fields. `Inbox` sets the ID and times; the history benchmark seeds with it.
    public init(
        id: UUID, kind: CaptureKind, createdAt: Date, lastUsedAt: Date, copyCount: Int, pinned: Bool,
        text: String?, fileName: String?, sourceApp: String?, sourceBundleID: String?, contentHash: String
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.copyCount = copyCount
        self.pinned = pinned
        self.text = text
        self.fileName = fileName
        self.sourceApp = sourceApp
        self.sourceBundleID = sourceBundleID
        self.contentHash = contentHash
    }
}

extension CaptureItem {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(CaptureKind.self, forKey: .kind)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt) ?? createdAt
        copyCount = try container.decodeIfPresent(Int.self, forKey: .copyCount) ?? 1
        pinned = try container.decode(Bool.self, forKey: .pinned)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp)
        sourceBundleID = try container.decodeIfPresent(String.self, forKey: .sourceBundleID)
        contentHash = try container.decode(String.self, forKey: .contentHash)
    }
}

extension CaptureItem {
    /// Histories below this size decode on one thread; splitting costs more than it saves.
    private static let parallelThreshold = 512 * 1024

    /// Decodes a `history.json` payload. A big file is cut at item boundaries and the pieces decode in
    /// parallel. If the file is not in the compact form `JSONEncoder` writes, or a piece fails, it decodes
    /// whole, so the result and the errors match a plain `JSONDecoder`.
    nonisolated static func decodeHistory(from data: Data) throws -> [CaptureItem] {
        if data.count >= parallelThreshold, let items = decodeInParallel(data) { return items }
        return try JSONDecoder().decode([CaptureItem].self, from: data)
    }

    private nonisolated static func decodeInParallel(_ data: Data) -> [CaptureItem]? {
        let pieces = min(ProcessInfo.processInfo.activeProcessorCount, 8)
        guard pieces > 1, data.first == UInt8(ascii: "["), data.last == UInt8(ascii: "]") else { return nil }
        // Inside a JSON string a quote is always escaped, so `},{"` only ever sits between two items.
        let separator: [UInt8] = Array("},{\"".utf8)
        let ranges: [Range<Int>]? = data.withUnsafeBytes { raw -> [Range<Int>]? in
            var cuts = [1]
            for piece in 1..<pieces {
                let from = max(cuts[cuts.count - 1], data.count * piece / pieces)
                guard from < data.count,
                      let found = memmem(raw.baseAddress! + from, data.count - from, separator, separator.count)
                else { break }
                cuts.append(raw.baseAddress!.distance(to: found) + 2)
            }
            cuts.append(data.count - 1)
            return zip(cuts, cuts.dropFirst()).map { $0..<$1 }
        }
        guard let ranges, ranges.count > 1 else { return nil }

        let results = Results(count: ranges.count)
        DispatchQueue.concurrentPerform(iterations: ranges.count) { index in
            var piece = Data([UInt8(ascii: "[")])
            piece.append(data[ranges[index]])
            piece.append(UInt8(ascii: "]"))
            results.set(index, try? JSONDecoder().decode([CaptureItem].self, from: piece))
        }
        return results.joined()
    }

    private final class Results: @unchecked Sendable {
        private let lock = NSLock()
        private var slots: [[CaptureItem]?]
        init(count: Int) { slots = Array(repeating: nil, count: count) }
        func set(_ index: Int, _ items: [CaptureItem]?) {
            lock.lock()
            slots[index] = items
            lock.unlock()
        }
        func joined() -> [CaptureItem]? {
            var all: [CaptureItem] = []
            for slot in slots {
                guard let slot else { return nil }
                all += slot
            }
            return all
        }
    }
}
