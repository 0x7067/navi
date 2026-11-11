import Foundation

/// Folded search keys for the history, so a search compares bytes instead of folding every item's text again.
///
/// Search ignores case, accents and character width, in every locale (see `SearchFold`): `acao` finds `ação`,
/// `CAFE` finds `café`. Every item gets a key; a search only skips items whose key is still being built.
struct SearchCache {
    /// The folded text and source app of one item.
    struct Key: Sendable {
        let text: [UInt8]
        let sourceApp: [UInt8]
    }

    /// Keys by item id. Read-only outside this type; tests check that evicted items lose their keys.
    private(set) var keys: [UUID: Key] = [:]

    /// Drops keys of items that are no longer in the history. Runs on every change to the list, so it returns
    /// early only when there is nothing to drop.
    mutating func prune(keeping items: [CaptureItem]) {
        guard !keys.isEmpty else { return }
        let live = Set(items.map(\.id))
        keys = keys.filter { live.contains($0.key) }
    }

    /// Builds the key for `item` unless it has one.
    mutating func prepare(_ item: CaptureItem) {
        _ = key(for: item)
    }

    /// Adds keys built elsewhere, for items that have none yet.
    mutating func install(_ built: [UUID: Key], for items: [CaptureItem]) {
        for item in items where keys[item.id] == nil {
            if let key = built[item.id] { keys[item.id] = key }
        }
    }

    /// True when every item has a key.
    func covers(_ items: [CaptureItem]) -> Bool {
        items.allSatisfy { keys[$0.id] != nil }
    }

    /// The items whose text or source app contains `query`, keeping the order of `items`.
    /// Keys that are missing are built here, but only until `budget` runs out. After that, items without a key are
    /// not matched and are counted in `deferred`; they match once their keys exist. Items above
    /// `Inbox.inlineKeyLimit` are never built here, so one huge text cannot overrun the budget; the background build
    /// makes them searchable.
    mutating func search(
        _ query: String, in items: [CaptureItem], budget: Duration
    ) -> (items: [CaptureItem], deferred: Int) {
        let needle = SearchFold.fold(query)
        guard !needle.isEmpty else { return (items, 0) }
        let deadline = ContinuousClock.now + budget
        var outOfTime = false
        var deferred = 0
        let found = items.filter { item in
            let key: Key
            if let cached = keys[item.id] {
                key = cached
            } else if Self.isHuge(item) {
                deferred += 1
                return false
            } else if outOfTime || ContinuousClock.now >= deadline {
                outOfTime = true
                deferred += 1
                return false
            } else {
                key = self.key(for: item)
            }
            return Self.contains(key.text, needle) || Self.contains(key.sourceApp, needle)
        }
        return (found, deferred)
    }

    /// Builds a key without touching any cache. Safe to call off the main actor.
    static func makeKey(text: String?, sourceApp: String?) -> Key {
        Key(text: SearchFold.fold(text ?? ""), sourceApp: SearchFold.fold(sourceApp ?? ""))
    }

    private mutating func key(for item: CaptureItem) -> Key {
        if let cached = keys[item.id] { return cached }
        let key = Self.makeKey(text: item.text, sourceApp: item.sourceApp)
        keys[item.id] = key
        return key
    }

    private static func isHuge(_ item: CaptureItem) -> Bool {
        (item.text?.utf8.count ?? 0) + (item.sourceApp?.utf8.count ?? 0) > Inbox.inlineKeyLimit
    }

    private static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard haystack.count >= needle.count else { return false }
        return haystack.withUnsafeBytes { h in
            needle.withUnsafeBytes { n in
                memmem(h.baseAddress, h.count, n.baseAddress, n.count) != nil
            }
        }
    }
}
