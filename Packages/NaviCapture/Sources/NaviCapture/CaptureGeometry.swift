import CoreGraphics
import Foundation

/// Pure math for capture: coordinate spaces, crops, snapping, and file names.
///
/// Coordinate spaces:
/// - Cocoa global: origin at the bottom left of the primary display, y goes up (`NSScreen.frame`).
/// - Quartz global: origin at the top left of the primary display, y goes down (`CGWindowList`, `SCWindow.frame`).
/// - View local: origin at the bottom left of one display, in points.
/// - Image pixels: origin at the top left of a captured image, in pixels.
public enum CaptureGeometry {
    /// Converts between Cocoa global and Quartz global rects. The formula is the same in both directions.
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The rect between two points, with positive width and height.
    public static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// `rect` moved by `offset`, kept inside `bounds`. The size never changes.
    public static func moved(_ rect: CGRect, by offset: CGVector, within bounds: CGRect) -> CGRect {
        var moved = rect.offsetBy(dx: offset.dx, dy: offset.dy)
        moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
        moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
        return moved
    }

    /// When `point` is within `tolerance` of a corner of `rect`, the opposite corner: drag from it to resize.
    public static func oppositeCorner(of rect: CGRect, near point: CGPoint, tolerance: CGFloat) -> CGPoint? {
        let corners = [
            (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.minY)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY)),
        ]
        return corners.first { hypot($0.0.x - point.x, $0.0.y - point.y) <= tolerance }?.1
    }

    /// The pixel rect in a screen image for a selection in view-local points.
    /// The result is whole pixels and stays inside the image.
    public static func pixelRect(forSelection selection: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let sx = imageSize.width / viewSize.width
        let sy = imageSize.height / viewSize.height
        let rect = CGRect(
            x: selection.minX * sx,
            y: (viewSize.height - selection.maxY) * sy,
            width: selection.width * sx,
            height: selection.height * sy
        ).integral
        return rect.intersection(CGRect(origin: .zero, size: imageSize))
    }

    /// The pixel under a view-local point, in image pixels.
    public static func pixel(at point: CGPoint, viewSize: CGSize, imageSize: CGSize) -> (x: Int, y: Int) {
        guard viewSize.width > 0, viewSize.height > 0 else { return (0, 0) }
        let x = Int((point.x * imageSize.width / viewSize.width).rounded(.down))
        let y = Int(((viewSize.height - point.y) * imageSize.height / viewSize.height).rounded(.down))
        return (min(max(x, 0), Int(imageSize.width) - 1), min(max(y, 0), Int(imageSize.height) - 1))
    }

    /// Moves `value` onto the nearest edge when it is within `tolerance`. Otherwise returns `value`.
    public static func snap(_ value: CGFloat, to edges: [CGFloat], tolerance: CGFloat) -> CGFloat {
        var best = value
        var bestDistance = tolerance
        for edge in edges {
            let distance = abs(edge - value)
            if distance <= bestDistance {
                best = edge
                bestDistance = distance
            }
        }
        return best
    }

    /// The file name for a capture, for example `Navi 2026-11-06 at 16.10.12.png`.
    public static func fileName(for date: Date, fileExtension: String, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Navi \(formatter.string(from: date)).\(fileExtension)"
    }

    /// A URL in `folder` for `name` that does not exist yet. Adds ` (2)`, ` (3)`, and so on when needed.
    public static func uniqueURL(in folder: URL, name: String, exists: (URL) -> Bool) -> URL {
        let first = folder.appending(path: name)
        guard exists(first) else { return first }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var number = 2
        while true {
            let candidate = folder.appending(path: ext.isEmpty ? "\(base) (\(number))" : "\(base) (\(number)).\(ext)")
            if !exists(candidate) { return candidate }
            number += 1
        }
    }
}
