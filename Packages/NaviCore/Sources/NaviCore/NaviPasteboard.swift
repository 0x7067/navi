import AppKit

/// Pasteboard helpers shared by features.
public enum NaviPasteboard {
    /// Marker type on pasteboard items that Navi writes itself. The clipboard watcher skips them,
    /// so a feature that already added the item to the Inbox does not get a second copy.
    public static let ownType = NSPasteboard.PasteboardType("com.donovanhiland.navi.own")

    /// Puts an image on the pasteboard with the Navi marker. Returns the new change count.
    @MainActor
    @discardableResult
    public static func write(image: NSImage, to pasteboard: NSPasteboard = .general) -> Int {
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        pasteboard.setData(Data(), forType: ownType)
        return pasteboard.changeCount
    }
}
