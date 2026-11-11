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
    public private(set) var items: [CaptureItem] = [] {
        didSet { searchCache.prune(keeping: items) }
    }
    public let directory: URL
    public var limit: Int

    @ObservationIgnored private let writer: HistoryWriter
    /// Files of removed items, handed to the writer with the next save so they go after the JSON.
    @ObservationIgnored private var doomedFiles: [URL] = []
    @ObservationIgnored private var searchCache = SearchCache()
    /// How long one search may spend building search keys that are still missing. Items without a key when it
    /// runs out are left out of that search; the background build finishes them and `searchKeysVersion` changes.
    @ObservationIgnored var searchBudget: Duration = .milliseconds(6)
    /// Changes each time the background build installs keys. `search` reads it, so a view that shows search
    /// results refreshes when more of the history becomes searchable.
    public private(set) var searchKeysVersion = 0
    /// How many items the last `search` left out because their keys were not built in time. Zero once the
    /// background build is done.
    @ObservationIgnored public private(set) var deferredSearchItems = 0
    @ObservationIgnored private let logger = Logger(subsystem: "com.donovanhiland.navi", category: "Inbox")
    private static let signposter = OSSignposter(subsystem: "com.donovanhiland.navi", category: "History")

    /// `~/Library/Application Support/Navi`. The test app, Navi Dev, keeps its own history in "Navi Dev".
    public static var defaultDirectory: URL {
        let name = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true ? "Navi Dev" : "Navi"
        return URL.applicationSupportDirectory.appending(path: name, directoryHint: .isDirectory)
    }

    public convenience init(directory: URL = Inbox.defaultDirectory, limit: Int = 200) {
        self.init(directory: directory, limit: limit, beforeDeleting: nil)
    }

    /// `beforeDeleting` is a test seam: it runs on the writer queue after a snapshot is written, before its deletions.
    init(directory: URL, limit: Int, beforeDeleting: (@Sendable () -> Void)?) {
        self.directory = directory
        self.limit = limit
        self.writer = HistoryWriter(directory: directory, beforeDeleting: beforeDeleting)
        load()
        warmSearch(items)
    }

    /// Blocks until the latest history is on disk. Call it when the app quits; saves otherwise run in the background.
    public func flush() {
        writer.flush()
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

    /// Adds file content, such as a PNG. The same content that is already in the history moves to the top,
    /// unless `deduplicate` is false. Captures pass false: each shot gets its own item, so its markup and
    /// file never belong to an older shot of the same pixels.
    @discardableResult
    public func add(
        fileData: Data, fileExtension: String, kind: CaptureKind,
        sourceApp: String? = nil, sourceBundleID: String? = nil, deduplicate: Bool = true, now: Date = .now
    ) -> CaptureItem? {
        let hash = Self.hash(fileData)
        if deduplicate, let existing = bump(hash: hash, kind: kind, now: now) { return existing }
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

    /// Replaces the file content of an item, for example after markup. The item keeps its place.
    @discardableResult
    public func updateFile(_ id: UUID, data: Data) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }),
              let url = fileURL(for: items[index])
        else { return false }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Could not update capture file: \(error.localizedDescription)")
            return false
        }
        items[index].contentHash = Self.hash(data)
        save()
        return true
    }

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
    /// Matching ignores case, accents and character width, over the text and the source app name (`acao` finds `ação`).
    public func search(_ query: String) -> [CaptureItem] {
        _ = searchKeysVersion
        let items = self.items
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        let found = searchCache.search(query, in: items, budget: searchBudget)
        deferredSearchItems = found.deferred
        return found.items
    }

    /// True once every item's search key is built. Searches work before that, only a little slower.
    public var isSearchReady: Bool { searchCache.covers(items) }

    /// The item's file content, or nil when the item has no file or it cannot be read.
    public func fileData(for id: UUID) -> Data? {
        guard let item = items.first(where: { $0.id == id }), let url = fileURL(for: item) else { return nil }
        return try? Data(contentsOf: url)
    }

    public func fileURL(for item: CaptureItem) -> URL? {
        item.fileName.map { filesDirectory.appending(path: $0) }
    }

    /// A PNG preview for items whose file is not an image, such as a recording. It may not exist.
    public func previewURL(for id: UUID) -> URL {
        filesDirectory.appending(path: "\(id.uuidString).preview.png")
    }

    /// Folder for an item's editable markup (`<id>.navi`). It may not exist yet.
    public func markupURL(for id: UUID) -> URL {
        filesDirectory.appending(path: "\(id.uuidString).navi", directoryHint: .isDirectory)
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
        // A new item is unpinned and normally newest, so an ordered insert replaces the full sort.
        let index = items.firstIndex { !$0.pinned && $0.lastUsedAt < item.lastUsedAt } ?? items.count
        items.insert(item, at: index)
        // A big text is folded in the background; a search before then builds it within its own budget.
        if (item.text?.utf8.count ?? 0) <= Self.inlineKeyLimit {
            searchCache.prepare(item)
        } else {
            warmSearch([item])
        }
        trimAndSave()
    }

    private func sortAndSave() {
        sort()
        save()
    }

    private func trimSortAndSave() {
        sort()
        trimAndSave()
    }

    private func trimAndSave() {
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
        doomedFiles.append(markupURL(for: item.id))
        doomedFiles.append(previewURL(for: item.id))
        if let url = fileURL(for: item) { doomedFiles.append(url) }
    }

    /// Texts up to this many UTF-8 bytes get their search key when added. Folding 16 KB of non-Latin text takes under 1 ms.
    nonisolated static let inlineKeyLimit = 16 * 1024

    /// Builds the search keys of `items` on a background task, then installs them here.
    private func warmSearch(_ items: [CaptureItem]) {
        let snapshot = items.map { ($0.id, $0.text, $0.sourceApp) }
        guard !snapshot.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            // In chunks, so results fill in as the build goes and a closed inbox stops it early.
            let chunk = 500
            var start = 0
            while start < snapshot.count {
                var built: [UUID: SearchCache.Key] = [:]
                for (id, text, sourceApp) in snapshot[start..<min(start + chunk, snapshot.count)] {
                    built[id] = SearchCache.makeKey(text: text, sourceApp: sourceApp)
                }
                guard let self else { return }
                await self.installSearchKeys(built)
                start += chunk
            }
        }
    }

    private func installSearchKeys(_ built: [UUID: SearchCache.Key]) {
        searchCache.install(built, for: items)
        searchKeysVersion += 1
    }

    private func load() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
        do {
            items = try CaptureItem.decodeHistory(from: data)
            sort()
        } catch {
            logger.error("Could not read history: \(error.localizedDescription)")
        }
    }

    private func save() {
        writer.write(items, deleting: doomedFiles)
        doomedFiles = []
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
