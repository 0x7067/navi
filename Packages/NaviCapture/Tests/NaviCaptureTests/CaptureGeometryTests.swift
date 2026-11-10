import CoreGraphics
import Foundation
import Testing

@testable import NaviCapture

@Suite struct CaptureGeometryTests {
    @Test func flipConvertsBothWays() {
        let cocoa = CGRect(x: 10, y: 100, width: 50, height: 20)
        let quartz = CaptureGeometry.flip(cocoa, primaryHeight: 1000)
        #expect(quartz == CGRect(x: 10, y: 880, width: 50, height: 20))
        #expect(CaptureGeometry.flip(quartz, primaryHeight: 1000) == cocoa)
    }

    @Test func rectFromAnyTwoCorners() {
        let rect = CaptureGeometry.rect(from: CGPoint(x: 30, y: 5), to: CGPoint(x: 10, y: 25))
        #expect(rect == CGRect(x: 10, y: 5, width: 20, height: 20))
    }

    @Test func pixelRectFlipsAndScalesForRetina() {
        // A 100 x 50 point view with a 2x image. The selection sits in the bottom-left corner.
        let rect = CaptureGeometry.pixelRect(
            forSelection: CGRect(x: 0, y: 0, width: 10, height: 10),
            viewSize: CGSize(width: 100, height: 50),
            imageSize: CGSize(width: 200, height: 100)
        )
        #expect(rect == CGRect(x: 0, y: 80, width: 20, height: 20))
    }

    @Test func pixelRectStaysInsideTheImage() {
        let rect = CaptureGeometry.pixelRect(
            forSelection: CGRect(x: 90, y: -5, width: 20, height: 20),
            viewSize: CGSize(width: 100, height: 50),
            imageSize: CGSize(width: 100, height: 50)
        )
        #expect(rect == CGRect(x: 90, y: 35, width: 10, height: 15))
    }

    @Test func pixelUnderPoint() {
        let pixel = CaptureGeometry.pixel(
            at: CGPoint(x: 10.6, y: 49.9), viewSize: CGSize(width: 100, height: 50), imageSize: CGSize(width: 200, height: 100)
        )
        #expect(pixel.x == 21)
        #expect(pixel.y == 0)
    }

    @Test func snapPicksTheNearestEdgeInTolerance() {
        #expect(CaptureGeometry.snap(103, to: [100, 105], tolerance: 6) == 105)
        #expect(CaptureGeometry.snap(103, to: [100, 200], tolerance: 6) == 100)
        #expect(CaptureGeometry.snap(120, to: [100, 200], tolerance: 6) == 120)
    }

    @Test func fileNameUsesTheCleanShotStyle() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = Date(timeIntervalSince1970: 1_793_982_612) // 2026-11-06 16:30:12 UTC
        #expect(CaptureGeometry.fileName(for: date, fileExtension: "png", timeZone: utc) == "Navi 2026-11-06 at 16.30.12.png")
    }

    @Test func uniqueURLAddsANumber() {
        let folder = URL(filePath: "/tmp/x", directoryHint: .isDirectory)
        let taken: Set<String> = ["/tmp/x/a.png", "/tmp/x/a (2).png"]
        let url = CaptureGeometry.uniqueURL(in: folder, name: "a.png") { taken.contains($0.path) }
        #expect(url.lastPathComponent == "a (3).png")
    }

    @Test func movingASelectionStaysOnScreen() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let rect = CGRect(x: 10, y: 10, width: 30, height: 20)
        #expect(CaptureGeometry.moved(rect, by: CGVector(dx: 5, dy: 5), within: bounds) == CGRect(x: 15, y: 15, width: 30, height: 20))
        #expect(CaptureGeometry.moved(rect, by: CGVector(dx: 500, dy: -50), within: bounds) == CGRect(x: 70, y: 0, width: 30, height: 20))
    }

    @Test func grabbingACornerAnchorsTheOppositeOne() {
        let rect = CGRect(x: 10, y: 10, width: 30, height: 20)
        #expect(CaptureGeometry.oppositeCorner(of: rect, near: CGPoint(x: 12, y: 9), tolerance: 8) == CGPoint(x: 40, y: 30))
        #expect(CaptureGeometry.oppositeCorner(of: rect, near: CGPoint(x: 41, y: 31), tolerance: 8) == CGPoint(x: 10, y: 10))
        #expect(CaptureGeometry.oppositeCorner(of: rect, near: CGPoint(x: 25, y: 20), tolerance: 8) == nil)
    }

    // Edit after capture: where the toolbar goes, in top-left coordinates.
    private static let screen = CGSize(width: 1000, height: 800)
    private static let bar = CGSize(width: 400, height: 40)

    @Test func toolbarGoesBelowTheAreaWhenThereIsRoom() {
        let area = CGRect(x: 300, y: 100, width: 200, height: 100)
        let origin = CaptureGeometry.toolbarOrigin(below: area, toolbar: Self.bar, in: Self.screen, gap: 8, margin: 10)
        #expect(origin == CGPoint(x: 200, y: 208))
    }

    @Test func toolbarGoesAboveTheAreaNearTheBottom() {
        let area = CGRect(x: 300, y: 600, width: 200, height: 180)
        let origin = CaptureGeometry.toolbarOrigin(below: area, toolbar: Self.bar, in: Self.screen, gap: 8, margin: 10)
        #expect(origin == CGPoint(x: 200, y: 552))
    }

    @Test func toolbarGoesInsideTheAreaWhenItFillsTheScreen() {
        let area = CGRect(origin: .zero, size: Self.screen)
        let origin = CaptureGeometry.toolbarOrigin(below: area, toolbar: Self.bar, in: Self.screen, gap: 8, margin: 10)
        #expect(origin == CGPoint(x: 300, y: 742))
    }

    @Test func toolbarStaysOnScreenAtTheSides() {
        let left = CGRect(x: 0, y: 100, width: 50, height: 50)
        let right = CGRect(x: 960, y: 100, width: 40, height: 50)
        #expect(CaptureGeometry.toolbarOrigin(below: left, toolbar: Self.bar, in: Self.screen, gap: 8, margin: 10).x == 10)
        #expect(CaptureGeometry.toolbarOrigin(below: right, toolbar: Self.bar, in: Self.screen, gap: 8, margin: 10).x == 590)
    }
}
