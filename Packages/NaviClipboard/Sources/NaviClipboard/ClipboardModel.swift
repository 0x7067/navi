import AppKit
import NaviCore
import Observation
import SwiftUI

/// Sizes for the history panel. Row heights are fixed so the panel can size itself to fit.
enum Metrics {
    static let width: CGFloat = 450
    static let headerHeight: CGFloat = 44
    static let textRowHeight: CGFloat = 24
    static let imageRowHeight: CGFloat = 50
    static let listPadding: CGFloat = 5
    static let footerRowHeight: CGFloat = 24
    static let footerHeight: CGFloat = 1 + footerRowHeight * 2 + listPadding * 2

    static func rowHeight(for item: CaptureItem) -> CGFloat {
        item.fileName == nil ? textRowHeight : imageRowHeight
    }
}

/// State for the history panel: the filter text, the selected row, and sizes.
@MainActor
@Observable
public final class ClipboardModel {
    let inbox: Inbox
    public var query = "" {
        didSet { selection = 0 }
    }
    var selection = 0 {
        didSet { onSelectionChange?() }
    }
    /// The tallest the list can be on the current screen.
    var maxListHeight: CGFloat = 600

    @ObservationIgnored var onSelectionChange: (() -> Void)?
    /// The part of the list content that is in view, in content coordinates.
    @ObservationIgnored var visibleRect = CGRect.zero
    /// Goes up on each open. The panel keeps one view, which scrolls to the top and focuses the search field on a change.
    private(set) var opens = 0
    /// True when the mouse set the selection. The list scrolls to the selection only for the keyboard.
    @ObservationIgnored var selectedByHover = false
    /// Mouse position at the last hover. Rows that move under a still mouse must not steal the selection.
    @ObservationIgnored var lastHoverLocation: CGPoint?

    /// Keyed by item ID and content hash, so an edited capture shows its new image.
    @ObservationIgnored private let images = NSCache<NSString, NSImage>()

    /// Creates the state for the history panel, reading from `inbox`.
    public init(inbox: Inbox) {
        self.inbox = inbox
    }

    /// The items that match the query, in display order.
    public var results: [CaptureItem] {
        let interval = HistorySignpost.signposter.beginInterval("Search")
        defer { HistorySignpost.signposter.endInterval("Search", interval) }
        return inbox.search(query)
    }

    var selectedItem: CaptureItem? { item(at: selection) }

    func item(at index: Int) -> CaptureItem? {
        let results = results
        return results.indices.contains(index) ? results[index] : nil
    }

    func listHeight(for results: [CaptureItem]) -> CGFloat {
        let rows = results.isEmpty
            ? Metrics.textRowHeight
            : results.reduce(0) { $0 + Metrics.rowHeight(for: $1) }
        return min(rows + Metrics.listPadding * 2, maxListHeight)
    }

    var contentHeight: CGFloat {
        Metrics.headerHeight + listHeight(for: results) + Metrics.footerHeight
    }

    /// Top and bottom of the row at `index`, in list content coordinates. Row heights are fixed.
    private func rowSpan(at index: Int, in results: [CaptureItem]) -> ClosedRange<CGFloat>? {
        guard results.indices.contains(index) else { return nil }
        let top = results[..<index].reduce(Metrics.listPadding) { $0 + Metrics.rowHeight(for: $1) }
        return top...(top + Metrics.rowHeight(for: results[index]))
    }

    /// Where to scroll so the row at `index` is in view, or nil when it already is.
    func scrollAnchor(for index: Int, in results: [CaptureItem]) -> UnitPoint? {
        guard let span = rowSpan(at: index, in: results) else { return nil }
        if span.lowerBound < visibleRect.minY { return .top }
        if span.upperBound > visibleRect.maxY { return .bottom }
        return nil
    }

    /// The middle of the selected row, measured down from the top of the panel. Places the preview card.
    var selectedRowMidY: CGFloat? {
        guard let span = rowSpan(at: selection, in: results) else { return nil }
        return Metrics.headerHeight + (span.lowerBound + span.upperBound) / 2 - visibleRect.minY
    }

    func reset() {
        query = ""
        selection = 0
        opens += 1
        lastHoverLocation = NSEvent.mouseLocation
    }

    func move(by offset: Int) {
        let count = results.count
        guard count > 0 else { return }
        selectedByHover = false
        selection = min(max(selection + offset, 0), count - 1)
    }

    /// Selects a row on hover, but only when the mouse really moved.
    func hover(_ index: Int) {
        let location = NSEvent.mouseLocation
        guard location != lastHoverLocation else { return }
        lastHoverLocation = location
        if selection != index {
            selectedByHover = true
            selection = index
        }
    }

    func togglePinSelected() {
        guard let item = selectedItem else { return }
        inbox.togglePin(item.id)
        if let index = results.firstIndex(where: { $0.id == item.id }) { selection = index }
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        inbox.remove(item.id)
        selection = min(selection, max(results.count - 1, 0))
    }

    func clear() {
        inbox.clearUnpinned()
        selection = 0
    }

    /// The full image of an item, for the preview card. Cached by item ID and content hash.
    public func image(for item: CaptureItem) -> NSImage? {
        let key = "\(item.id.uuidString)-\(item.contentHash)" as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let url = imageURL(for: item), let image = NSImage(contentsOf: url) else { return nil }
        images.setObject(image, forKey: key)
        return image
    }

    /// The row thumbnail of an item, if it is already decoded.
    func cachedThumbnail(for item: CaptureItem) -> NSImage? {
        images.object(forKey: thumbnailKey(item))
    }

    /// The row thumbnail of an item: a small copy decoded off the main actor, so a row never waits for a full image.
    func thumbnail(for item: CaptureItem) async -> NSImage? {
        if let cached = cachedThumbnail(for: item) { return cached }
        guard let url = imageURL(for: item) else { return nil }
        let interval = HistorySignpost.signposter.beginInterval("RowImage")
        let decoded = await Task.detached(priority: .userInitiated) { Self.downsample(url) }.value
        HistorySignpost.signposter.endInterval("RowImage", interval)
        guard let decoded else { return nil }
        let image = NSImage(cgImage: decoded, size: .zero)
        images.setObject(image, forKey: thumbnailKey(item))
        return image
    }

    private func thumbnailKey(_ item: CaptureItem) -> NSString {
        "\(item.id.uuidString)-\(item.contentHash)-thumbnail" as NSString
    }

    private func imageURL(for item: CaptureItem) -> URL? {
        let preview = inbox.previewURL(for: item.id)
        return FileManager.default.fileExists(atPath: preview.path) ? preview : inbox.fileURL(for: item)
    }

    /// Decodes `url` at no more than 400 pixels on its long side: the row shows it at 200 × 40 points.
    private nonisolated static func downsample(_ url: URL) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 400,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
