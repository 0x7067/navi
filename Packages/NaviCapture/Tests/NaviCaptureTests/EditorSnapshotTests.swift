import AppKit
import SwiftUI
import Testing

@testable import NaviCapture

/// Draws the markup editor to PNG files so its look can be checked without a screen.
/// Off by default. Run: NAVI_SNAPSHOTS=/tmp/navi-snaps swift test --filter EditorSnapshot
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["NAVI_SNAPSHOTS"] != nil))
struct EditorSnapshotTests {
    @Test(arguments: [760, 1000, 1400])
    func editor(width: Int) throws {
        let folder = URL(filePath: ProcessInfo.processInfo.environment["NAVI_SNAPSHOTS"]!)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let context = CGContext(
            data: nil, width: 1200, height: 700, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 0.35, green: 0.55, blue: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 700))
        let model = AnnotateModel(base: context.makeImage()!, scale: 2)
        model.tool = .rectangle
        model.pointerDown(at: CGPoint(x: 200, y: 150))
        model.pointerDragged(from: CGPoint(x: 200, y: 150), to: CGPoint(x: 700, y: 450))
        model.pointerUp(from: CGPoint(x: 200, y: 150), to: CGPoint(x: 700, y: 450))

        for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            let view = NSHostingView(rootView: AnnotateView(model: model, onDone: {}, onCancel: {}))
            view.appearance = NSAppearance(named: appearance)
            view.frame = CGRect(x: 0, y: 0, width: width, height: 420)
            view.layoutSubtreeIfNeeded()
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: folder.appending(path: "editor-\(width)-\(name).png"))
        }
    }
}
