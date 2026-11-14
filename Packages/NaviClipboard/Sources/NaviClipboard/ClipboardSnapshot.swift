import AppKit

enum ClipboardSnapshot {
    static let maxBytes = 32 * 1024 * 1024

    static func read(_ pasteboard: NSPasteboard) -> [[String: Data]]? {
        var total = 0
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [String: Data]()) { entries, type in
                guard let data = item.data(forType: type) else { return }
                total += data.count
                entries[type.rawValue] = data
            }
        }
        return items.isEmpty || total > maxBytes ? nil : items
    }

    static func save(_ items: [[String: Data]], to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? PropertyListSerialization.data(fromPropertyList: items, format: .binary, options: 0).write(to: url, options: .atomic)
    }

    static func load(_ url: URL) -> [[String: Data]]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Data]]
    }

    static func write(_ items: [[String: Data]], to pasteboard: NSPasteboard) {
        let objects = items.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries {
                item.setData(data, forType: .init(type))
            }
            return item
        }
        pasteboard.writeObjects(objects)
    }
}
