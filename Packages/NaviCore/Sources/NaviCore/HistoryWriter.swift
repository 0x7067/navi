import Foundation
import os

/// Encodes and writes `history.json` off the main actor.
///
/// Ordering: every snapshot goes through one slot (`pending`) and one serial queue. A newer snapshot
/// replaces an older one that has not started writing, so bursts coalesce and the latest wins. The serial
/// queue runs one drain at a time, and each drain takes whatever is newest at that moment, so an older
/// snapshot can never overwrite a newer one. `flush()` waits on the same queue, so when it returns
/// every snapshot handed over before the call is on disk.
///
/// Deletions: files of removed items are deleted only after a snapshot that no longer references them
/// is written atomically, so a crash leaves an orphan file, never a dangling reference. Deletions from
/// coalesced snapshots accumulate and run after the newest snapshot. A file the written snapshot still
/// references is skipped. `flush()` waits for deletions too.
final class HistoryWriter: Sendable {
    private struct State {
        var pending: [CaptureItem]?
        var doomed: [URL] = []
        var drainQueued = false
    }

    private let directory: URL
    private let queue = DispatchQueue(label: "com.donovanhiland.navi.history-writer", qos: .utility)
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let logger = Logger(subsystem: "com.donovanhiland.navi", category: "Inbox")
    private static let signposter = OSSignposter(subsystem: "com.donovanhiland.navi", category: "History")

    private let beforeDeleting: (@Sendable () -> Void)?

    init(directory: URL, beforeDeleting: (@Sendable () -> Void)? = nil) {
        self.directory = directory
        self.beforeDeleting = beforeDeleting
    }

    /// Hands over a snapshot to write and the files to delete once it is on disk. Returns at once.
    func write(_ items: [CaptureItem], deleting files: [URL] = []) {
        let needsDrain = state.withLock { state in
            state.pending = items
            state.doomed += files
            defer { state.drainQueued = true }
            return !state.drainQueued
        }
        if needsDrain { queue.async { self.drain() } }
    }

    /// Blocks until every snapshot handed over so far is written.
    func flush() {
        queue.sync {}
    }

    private func drain() {
        while let (items, doomed) = state.withLock({ state -> ([CaptureItem], [URL])? in
            guard let items = state.pending else {
                state.drainQueued = false
                return nil
            }
            defer { state.pending = nil; state.doomed = [] }
            return (items, state.doomed)
        }) {
            let saved = persist(items)
            beforeDeleting?()
            // If the write failed, the old JSON may still reference these files, so keep them.
            guard saved else { continue }
            let referenced = Set(items.compactMap(\.fileName))
            for url in doomed where !referenced.contains(url.lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func persist(_ items: [CaptureItem]) -> Bool {
        let interval = Self.signposter.beginInterval("InboxSave")
        defer { Self.signposter.endInterval("InboxSave", interval) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items)
            try data.write(to: directory.appending(path: "history.json"), options: .atomic)
            return true
        } catch {
            logger.error("Could not save history: \(error.localizedDescription)")
            return false
        }
    }
}
