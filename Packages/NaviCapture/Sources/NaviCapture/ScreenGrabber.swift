import AppKit
import ScreenCaptureKit

/// A captured image and its points-to-pixels scale.
struct CapturedImage {
    let image: CGImage
    let scale: CGFloat
}

/// One window on screen, for window mode. `frame` is in Cocoa global coordinates.
struct OnScreenWindow {
    let id: CGWindowID
    let frame: CGRect
}

enum CaptureError: Error {
    case noDisplay
    case noWindow
}

/// Takes pictures of displays and windows with ScreenCaptureKit.
@MainActor
enum ScreenGrabber {
    static let finderBundleID = "com.apple.finder"

    /// Captures every display, without Navi's overlays and cards. Used to freeze the screen before a selection.
    static func captureAllScreens(hideDesktopIcons: Bool) async throws -> [(NSScreen, CapturedImage)] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var result: [(NSScreen, CapturedImage)] = []
        for screen in NSScreen.screens {
            result.append((screen, try await capture(screen, content: content, hideDesktopIcons: hideDesktopIcons)))
        }
        return result
    }

    /// Captures one display, without Navi's overlays and cards.
    static func capture(_ screen: NSScreen, hideDesktopIcons: Bool) async throws -> CapturedImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return try await capture(screen, content: content, hideDesktopIcons: hideDesktopIcons)
    }

    /// Captures part of a display. `rect` is in display-local points with the origin at the top left.
    static func capture(_ screen: NSScreen, rect: CGRect, hideDesktopIcons: Bool) async throws -> CapturedImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return try await capture(screen, content: content, hideDesktopIcons: hideDesktopIcons, sourceRect: rect)
    }

    /// Captures one window alone, with its shadow and a clear background. Nothing behind it gets in.
    static func captureWindow(id: CGWindowID) async throws -> CapturedImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError.noWindow }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * scale)
        config.height = Int(filter.contentRect.height * scale)
        config.captureResolution = .best
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = false
        config.shouldBeOpaque = false
        config.backgroundColor = .clear
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return CapturedImage(image: image, scale: scale)
    }

    /// Normal app windows on screen, front to back. Navi's own normal windows (such as the markup
    /// editor) count too; its overlays, cards, and pills are above layer 0, so they never do.
    static func onScreenWindows() -> [OnScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width > 20, bounds.height > 20
            else { return nil }
            return OnScreenWindow(id: number, frame: CaptureGeometry.flip(bounds, primaryHeight: primaryHeight))
        }
    }

    private static func capture(
        _ screen: NSScreen, content: SCShareableContent, hideDesktopIcons: Bool, sourceRect: CGRect? = nil
    ) async throws -> CapturedImage {
        guard let displayID = screen.displayID,
              let display = content.displays.first(where: { $0.displayID == displayID })
        else { throw CaptureError.noDisplay }

        let ownBundleID = Bundle.main.bundleIdentifier
        let excluded = content.windows.filter { window in
            let bundleID = window.owningApplication?.bundleIdentifier
            // Leave out Navi's overlays, cards, pins, and pills (all above layer 0), but keep its
            // normal windows, such as the markup editor, so you can take a shot of them.
            if bundleID == ownBundleID { return window.windowLayer != 0 }
            // Finder draws desktop icons in windows below the normal window layer.
            return hideDesktopIcons && bundleID == finderBundleID && window.windowLayer < 0
        }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        if let sourceRect {
            config.sourceRect = sourceRect
            config.width = Int(sourceRect.width * scale)
            config.height = Int(sourceRect.height * scale)
        } else {
            config.width = Int(screen.frame.width * scale)
            config.height = Int(screen.frame.height * scale)
        }
        config.captureResolution = .best
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return CapturedImage(image: image, scale: scale)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// The display under the mouse.
    static var underMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main
    }
}
