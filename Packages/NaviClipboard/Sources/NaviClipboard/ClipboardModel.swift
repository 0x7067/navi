import AppKit
import NaviCore
import Observation

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
final class ClipboardModel {
    let inbox: Inbox
    var query = "" {
        didSet { selection = 0 }
    }
    var selection = 0 {
        didSet { onSelectionChange?() }
    }
    /// The tallest the list can be on the current screen.
    var maxListHeight: CGFloat = 600

    @ObservationIgnored var onSelectionChange: (() -> Void)?
    /// Row frames in panel coordinates (top-left origin). Used to place the preview next to its row.
    @ObservationIgnored var rowFrames: [UUID: CGRect] = [:]
    /// Mouse position at the last hover. Rows that move under a still mouse must not steal the selection.
    @ObservationIgnored var lastHoverLocation: CGPoint?

    /// Keyed by item ID and content hash, so an edited capture shows its new image.
    @ObservationIgnored private let images = NSCache<NSString, NSImage>()

    init(inbox: Inbox) {
        self.inbox = inbox
    }

    var results: [CaptureItem] { inbox.search(query) }

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

    func reset() {
        query = ""
        selection = 0
        rowFrames = [:]
        lastHoverLocation = NSEvent.mouseLocation
    }

    func move(by offset: Int) {
        let count = results.count
        guard count > 0 else { return }
        selection = min(max(selection + offset, 0), count - 1)
    }

    /// Selects a row on hover, but only when the mouse really moved.
    func hover(_ index: Int) {
        let location = NSEvent.mouseLocation
        guard location != lastHoverLocation else { return }
        lastHoverLocation = location
        if selection != index { selection = index }
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

    func image(for item: CaptureItem) -> NSImage? {
        let key = "\(item.id.uuidString)-\(item.contentHash)" as NSString
        if let cached = images.object(forKey: key) { return cached }
        let preview = inbox.previewURL(for: item.id)
        let url = FileManager.default.fileExists(atPath: preview.path) ? preview : inbox.fileURL(for: item)
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        images.setObject(image, forKey: key)
        return image
    }
}
