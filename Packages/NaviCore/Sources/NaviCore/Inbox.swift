import CryptoKit
import Foundation
import Observation
import os

/// The shared history of all captures. Features add items here; the history UI reads from here.
///
/// Order: pinned items first, then newest first. Unpinned items above `limit` are dropped.
/// Items persist as `history.json` plus a `files/` folder inside `directory`.
@MainActor
@Observable
public final class Inbox {
    public private(set) var items: [CaptureItem] = []
    public let directory: URL
    public var limit: Int

    @ObservationIgnored private let logger = Logger(subsystem: "com.donovanhiland.navi", category: "Inbox")

    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Navi", directoryHint: .isDirectory)
    }

    public init(directory: URL = Inbox.defaultDirectory, limit: Int = 200) {
        self.directory = directory
        self.limit = limit
        load()
    }

    // MARK: Adding

    /// Adds text. Blank text is ignored. Text that is already in the history moves to the top
    /// and its copy count goes up.
    @discardableResult
    public func add(
        text: String, kind: CaptureKind = .text, sourceApp: String? = nil, sourceBundleID: String? = nil, now: Date = .now
    ) -> CaptureItem? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let hash = Self.hash(Data(text.utf8))
        if let existing = bump(hash: hash, kind: kind, now: now) { return existing }
        let item = CaptureItem(
            id: UUID(), kind: kind, createdAt: now, lastUsedAt: now, copyCount: 1, pinned: false,
            text: text, fileName: nil, sourceApp: sourceApp, sourceBundleID: sourceBundleID, contentHash: hash
        )
        insert(item)
        return item
    }

    /// Adds file content, such as a PNG. The same content that is already in the history moves to the top.
    @discardableResult
    public func add(
        fileData: Data, fileExtension: String, kind: CaptureKind,
        sourceApp: String? = nil, sourceBundleID: String? = nil, now: Date = .now
    ) -> CaptureItem? {
        let hash = Self.hash(fileData)
        if let existing = bump(hash: hash, kind: kind, now: now) { return existing }
        let id = UUID()
        let name = "\(id.uuidString).\(fileExtension)"
        do {
            try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
            try fileData.write(to: filesDirectory.appending(path: name), options: .atomic)
        } catch {
            logger.error("Could not write capture file: \(error.localizedDescription)")
            return nil
        }
        let item = CaptureItem(
            id: id, kind: kind, createdAt: now, lastUsedAt: now, copyCount: 1, pinned: false,
            text: nil, fileName: name, sourceApp: sourceApp, sourceBundleID: sourceBundleID, contentHash: hash
        )
        insert(item)
        return item
    }

    // MARK: Changing

    /// Moves an item to the top of its group (pinned or unpinned). Used after a paste.
    public func touch(_ id: UUID, now: Date = .now) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].lastUsedAt = now
        sortAndSave()
    }

    public func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
        trimSortAndSave()
    }

    public func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        deleteFile(of: items[index])
        items.remove(at: index)
        save()
    }

    public func clearUnpinned() {
        for item in items where !item.pinned { deleteFile(of: item) }
        items.removeAll { !$0.pinned }
        save()
    }

    // MARK: Reading

    /// Items that match `query`, in display order. An empty query returns all items.
    public func search(_ query: String) -> [CaptureItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            (item.text?.localizedCaseInsensitiveContains(query) ?? false)
                || (item.sourceApp?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    public func fileURL(for item: CaptureItem) -> URL? {
        item.fileName.map { filesDirectory.appending(path: $0) }
    }

    // MARK: Private

    private var historyURL: URL { directory.appending(path: "history.json") }
    private var filesDirectory: URL { directory.appending(path: "files", directoryHint: .isDirectory) }

    private func bump(hash: String, kind: CaptureKind, now: Date) -> CaptureItem? {
        guard let index = items.firstIndex(where: { $0.contentHash == hash && $0.kind == kind }) else { return nil }
        items[index].lastUsedAt = now
        items[index].copyCount += 1
        let item = items[index]
        sortAndSave()
        return item
    }

    private func insert(_ item: CaptureItem) {
        items.append(item)
        trimSortAndSave()
    }

    private func sortAndSave() {
        sort()
        save()
    }

    private func trimSortAndSave() {
        sort()
        var unpinnedCount = 0
        var kept: [CaptureItem] = []
        for item in items {
            if item.pinned {
                kept.append(item)
                continue
            }
            unpinnedCount += 1
            if unpinnedCount <= limit {
                kept.append(item)
            } else {
                deleteFile(of: item)
            }
        }
        items = kept
        save()
    }

    private func sort() {
        items.sort { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.lastUsedAt > rhs.lastUsedAt
        }
    }

    private func deleteFile(of item: CaptureItem) {
        guard let url = fileURL(for: item) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func load() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
        do {
            items = try JSONDecoder().decode([CaptureItem].self, from: data)
            sort()
        } catch {
            logger.error("Could not read history: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items)
            try data.write(to: historyURL, options: .atomic)
        } catch {
            logger.error("Could not save history: \(error.localizedDescription)")
        }
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
