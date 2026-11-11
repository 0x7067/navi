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
    /// The largest image the preview card shows, in points.
    static let previewMaxWidth: CGFloat = 480
    static let previewMaxHeight: CGFloat = 360

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
        didSet { select(0) }
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
    /// Thumbnails being decoded now, by cache key, so a prewarm and a row never decode the same image twice.
    @ObservationIgnored private var decoding: [NSString: Task<CGImage?, Never>] = [:]
    /// Icons of the apps items were copied from, by bundle ID.
    @ObservationIgnored private var appIcons: [String: NSImage] = [:]
    /// The last search and what it was made from.
    @ObservationIgnored private var lastSearch: (query: String, items: Int, keys: Int, results: [CaptureItem])?

    /// Creates the state for the history panel, reading from `inbox`.
    public init(inbox: Inbox) {
        self.inbox = inbox
    }

    /// The items that match the query, in display order. The last search is reused until the query or the history changes.
    public var results: [CaptureItem] {
        // Read the inputs every time, so a caller that observes `results` still tracks them.
        let query = self.query
        _ = inbox.items
        // Read before the search, which reads the keys version too.
        let items = inbox.itemsVersion, keys = inbox.searchKeysVersion
        if let lastSearch, lastSearch.query == query, lastSearch.items == items, lastSearch.keys == keys {
            return lastSearch.results
        }
        let interval = HistorySignpost.signposter.beginInterval("Search")
        let results = inbox.search(query)
        HistorySignpost.signposter.endInterval("Search", interval)
        lastSearch = (query, items, keys, results)
        return results
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
        select(0)
        opens += 1
        lastHoverLocation = NSEvent.mouseLocation
    }

    func move(by offset: Int) {
        let count = results.count
        guard count > 0 else { return }
        select(min(max(selection + offset, 0), count - 1))
    }

    /// Selects a row from the keyboard or the app, so the list scrolls to it.
    private func select(_ index: Int) {
        selectedByHover = false
        selection = index
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
        if let index = results.firstIndex(where: { $0.id == item.id }) { select(index) }
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        inbox.remove(item.id)
        select(min(selection, max(results.count - 1, 0)))
    }

    func clear() {
        inbox.clearUnpinned()
        select(0)
    }

    /// The row thumbnail of an item, if it is already decoded.
    func cachedThumbnail(for item: CaptureItem) -> NSImage? {
        images.object(forKey: thumbnailKey(item))
    }

    /// The row thumbnail of an item: a copy of at most 400 pixels, decoded off the main actor, so a row never waits for a full image.
    func thumbnail(for item: CaptureItem) async -> NSImage? {
        if let cached = cachedThumbnail(for: item) { return cached }
        let key = thumbnailKey(item)
        let task: Task<CGImage?, Never>
        if let existing = decoding[key] {
            task = existing
        } else {
            guard let file = inbox.fileURL(for: item) else { return nil }
            let preview = inbox.previewURL(for: item.id)
            let maxPixelSize = 400
            task = Task.detached(priority: .userInitiated) {
                Self.downsample(preview, maxPixelSize: maxPixelSize) ?? Self.downsample(file, maxPixelSize: maxPixelSize)
            }
            decoding[key] = task
        }
        let interval = HistorySignpost.signposter.beginInterval("RowImage")
        let decoded = await task.value
        HistorySignpost.signposter.endInterval("RowImage", interval)
        decoding[key] = nil
        if let cached = cachedThumbnail(for: item) { return cached }
        guard let decoded else { return nil }
        let image = NSImage(cgImage: decoded, size: .zero)
        images.setObject(image, forKey: key)
        return image
    }

    /// How many rows from the top get their thumbnail ahead of time: more than one screen of rows.
    static let warmRows = 40

    /// Decodes the thumbnails of the first image rows now, and again each time the history changes,
    /// so the panel opens with its images already there.
    func keepThumbnailsWarm() {
        let items = withObservationTracking { inbox.items } onChange: { [weak self] in
            Task { @MainActor in self?.keepThumbnailsWarm() }
        }
        for item in items.prefix(Self.warmRows) where item.fileName != nil && cachedThumbnail(for: item) == nil {
            Task { _ = await thumbnail(for: item) }
        }
    }

    /// The image for the preview card: decoded off the main actor, no bigger than the card shows it on a 2x screen.
    /// It keeps the point size the full image would have, so small images are not scaled up.
    func previewImage(for item: CaptureItem) async -> NSImage? {
        let key = "\(item.id.uuidString)-\(item.contentHash)-preview" as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let file = inbox.fileURL(for: item) else { return nil }
        let preview = inbox.previewURL(for: item.id)
        let maxPixelSize = Int(Metrics.previewMaxWidth * 2)
        let decoded = await Task.detached(priority: .userInitiated) {
            Self.decodeForCard(preview, maxPixelSize: maxPixelSize) ?? Self.decodeForCard(file, maxPixelSize: maxPixelSize)
        }.value
        guard let decoded else { return nil }
        let image = NSImage(cgImage: decoded.image, size: decoded.pointSize)
        images.setObject(image, forKey: key)
        return image
    }

    /// The icon of the app an item was copied from. Looked up once per app.
    func appIcon(for item: CaptureItem) -> NSImage? {
        guard let bundleID = item.sourceBundleID else { return nil }
        if let cached = appIcons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIcons[bundleID] = icon
        return icon
    }

    private func thumbnailKey(_ item: CaptureItem) -> NSString {
        "\(item.id.uuidString)-\(item.contentHash)-thumbnail" as NSString
    }

    /// Options for a thumbnail no bigger than `maxPixelSize` on its long side, turned upright.
    private nonisolated static func thumbnailOptions(maxPixelSize: Int) -> CFDictionary {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return options as CFDictionary
    }

    /// Decodes `url` at no more than `maxPixelSize` pixels on its long side.
    private nonisolated static func downsample(_ url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions(maxPixelSize: maxPixelSize))
    }

    /// Decodes `url` for the preview card: a copy no bigger than `maxPixelSize` on its long side, and the size the
    /// full image has in points at its dpi (72 when unknown), so the card shows it at its real size.
    private nonisolated static func decodeForCard(_ url: URL, maxPixelSize: Int) -> (image: CGImage, pointSize: CGSize)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions(maxPixelSize: maxPixelSize))
        else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        let dpiValue = dpi > 0 ? dpi : 72
        let thumbLong = Double(max(thumb.width, thumb.height))
        let pixelWidth = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue
        let pixelHeight = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
        var fullLong = thumbLong
        if let pixelWidth, let pixelHeight {
            fullLong = max(pixelWidth, pixelHeight) * 72 / dpiValue
        }
        let factor = fullLong / thumbLong
        let pointSize = CGSize(width: Double(thumb.width) * factor, height: Double(thumb.height) * factor)
        return (image: thumb, pointSize: pointSize)
    }
}
