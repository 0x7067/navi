import CoreGraphics
import Foundation
import Testing
@testable import NaviRecording

@Suite("RecordingMath")
struct RecordingMathTests {
    @Test func videoSizeIsEvenAndRetina() {
        let size = RecordingMath.videoPixelSize(points: CGSize(width: 501, height: 301), scale: 2)
        #expect(size.width == 1002)
        #expect(size.height == 602)
        let odd = RecordingMath.videoPixelSize(points: CGSize(width: 100.5, height: 50.5), scale: 1)
        #expect(odd.width == 100)
        #expect(odd.height == 50)
    }

    @Test func videoSizeShrinksPastTheLimitAndKeepsShape() {
        let size = RecordingMath.videoPixelSize(points: CGSize(width: 2560, height: 1440), scale: 2)
        #expect(size.width == 4096)
        #expect(size.height == 2304)
    }

    @Test func videoSizeHasAMinimum() {
        let size = RecordingMath.videoPixelSize(points: .zero, scale: 2)
        #expect(size.width == 2)
        #expect(size.height == 2)
    }

    @Test func bitRateStaysInRange() {
        #expect(RecordingMath.videoBitRate(width: 100, height: 100, framesPerSecond: 30) == 4_000_000)
        #expect(RecordingMath.videoBitRate(width: 4096, height: 2304, framesPerSecond: 60) == 39_636_172)
        #expect(RecordingMath.videoBitRate(width: 8000, height: 8000, framesPerSecond: 60) == 60_000_000)
    }

    @Test func gifPlanCountsFramesAndKeepsThemInside() {
        let plan = RecordingMath.gifPlan(duration: 2, naturalSize: CGSize(width: 1600, height: 900))
        #expect(plan.times.count == 30)
        #expect(abs(plan.frameDelay - 1.0 / 15.0) < 1e-9)
        #expect(plan.width == 800)
        #expect(plan.height == 450)
        #expect(plan.times.first! > 0)
        #expect(plan.times.last! < 2)
        #expect(plan.times == plan.times.sorted())
    }

    @Test func gifPlanDoesNotUpscaleAndHandlesTinyClips() {
        let plan = RecordingMath.gifPlan(duration: 0, naturalSize: CGSize(width: 400, height: 300))
        #expect(plan.times.count == 1)
        #expect(plan.times[0] >= 0)
        #expect(plan.width == 400)
        #expect(plan.height == 300)
    }

    @Test func gifPlanRoundsPartialFramesUp() {
        let plan = RecordingMath.gifPlan(duration: 1.01, naturalSize: CGSize(width: 800, height: 600))
        #expect(plan.times.count == 16)
    }

    @Test func flipWorksBothWays() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
        let flipped = RecordingMath.flip(rect, primaryHeight: 1000)
        #expect(flipped == CGRect(x: 10, y: 930, width: 100, height: 50))
        #expect(RecordingMath.flip(flipped, primaryHeight: 1000) == rect)
    }

    @Test func localRectBecomesCocoaRect() {
        let display = CGRect(x: -1440, y: 100, width: 1440, height: 900)
        let local = CGRect(x: 100, y: 50, width: 400, height: 300)
        let cocoa = RecordingMath.cocoaRect(forLocal: local, displayFrame: display)
        #expect(cocoa == CGRect(x: -1340, y: 650, width: 400, height: 300))
    }

    @Test func barGoesBelowTheRegion() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = RecordingMath.barFrame(
            region: CGRect(x: 400, y: 400, width: 400, height: 300), barSize: CGSize(width: 300, height: 140), visible: visible
        )
        #expect(frame.midX == 600)
        #expect(frame.maxY <= 400 - 12 + 0.001)
    }

    @Test func barGoesAboveWhenThereIsNoRoomBelow() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let region = CGRect(x: 400, y: 20, width: 400, height: 300)
        let frame = RecordingMath.barFrame(region: region, barSize: CGSize(width: 300, height: 140), visible: visible)
        #expect(frame.minY >= region.maxY)
    }

    @Test func barGoesInsideForAFullDisplayRegion() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = RecordingMath.barFrame(region: visible, barSize: CGSize(width: 300, height: 140), visible: visible)
        #expect(visible.contains(frame))
    }

    @Test func barStaysOnTheScreenHorizontally() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = RecordingMath.barFrame(
            region: CGRect(x: 0, y: 400, width: 100, height: 100), barSize: CGSize(width: 300, height: 140), visible: visible
        )
        #expect(frame.minX >= 8)
    }

    @Test func typedSizeIsInPixelsAndStaysOnTheDisplay() {
        let display = CGSize(width: 1440, height: 900)
        let area = CGRect(x: 1300, y: 800, width: 100, height: 50)
        let resized = RecordingMath.resizedArea(area, toPixelWidth: 800, height: 600, scale: 2, displaySize: display)
        #expect(resized.size == CGSize(width: 400, height: 300))
        #expect(resized.maxX <= 1440)
        #expect(resized.maxY <= 900)
    }

    @Test func typedSizeIsClamped() {
        let display = CGSize(width: 1440, height: 900)
        let tiny = RecordingMath.resizedArea(CGRect(x: 0, y: 0, width: 100, height: 100), toPixelWidth: 2, height: 2, scale: 2, displaySize: display)
        #expect(tiny.size == CGSize(width: 40, height: 40))
        let huge = RecordingMath.resizedArea(CGRect(x: 50, y: 50, width: 100, height: 100), toPixelWidth: 99_999, height: 99_999, scale: 2, displaySize: display)
        #expect(huge == CGRect(x: 0, y: 0, width: 1440, height: 900))
    }

    @Test func elapsedLabels() {
        #expect(RecordingMath.elapsedLabel(0) == "0:00")
        #expect(RecordingMath.elapsedLabel(12.9) == "0:12")
        #expect(RecordingMath.elapsedLabel(65) == "1:05")
        #expect(RecordingMath.elapsedLabel(3669) == "1:01:09")
        #expect(RecordingMath.elapsedLabel(-5) == "0:00")
    }

    @Test func fileNameMatchesTheScreenshotStyle() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 16, minute: 10, second: 12))!
        let name = RecordingMath.fileName(for: date, fileExtension: "mp4", timeZone: TimeZone(identifier: "UTC")!)
        #expect(name == "Navi 2026-11-06 at 16.10.12.mp4")
    }
}

@Suite("KeyLabel")
struct KeyLabelTests {
    @Test func shortcutsShowModifiersInMacOrder() {
        let text = KeyLabel.text(keyCode: 21, flags: [.maskShift, .maskCommand], character: "4")
        #expect(text == "⇧⌘4")
        #expect(KeyLabel.text(keyCode: 8, flags: [.maskCommand, .maskControl, .maskAlternate, .maskShift], character: "c") == "⌃⌥⇧⌘C")
    }

    @Test func plainTypingNeverShows() {
        #expect(KeyLabel.text(keyCode: 0, flags: [], character: "a") == nil)
        #expect(KeyLabel.text(keyCode: 0, flags: [.maskShift], character: "A") == nil)
    }

    @Test func specialKeysShowAlone() {
        #expect(KeyLabel.text(keyCode: 36, flags: [], character: "\r") == "⏎")
        #expect(KeyLabel.text(keyCode: 123, flags: [.maskAlternate], character: nil) == "⌥←")
        #expect(KeyLabel.text(keyCode: 49, flags: [.maskCommand], character: " ") == "⌘Space")
        #expect(KeyLabel.text(keyCode: 122, flags: [], character: nil) == "F1")
    }

    @Test func unknownKeysWithoutACharacterShowNothing() {
        #expect(KeyLabel.text(keyCode: 200, flags: [.maskCommand], character: nil) == nil)
        #expect(KeyLabel.text(keyCode: 200, flags: [.maskCommand], character: "\u{1}") == nil)
    }
}

@Suite("TrimRange")
struct TrimRangeTests {
    @Test func fullRangeMeansNoCut() {
        #expect(TrimRange.resolve(start: nil, end: nil, duration: 10) == nil)
        #expect(TrimRange.resolve(start: 0.01, end: 9.99, duration: 10) == nil)
    }

    @Test func partialRangeIsKept() {
        let range = TrimRange.resolve(start: 2, end: 8, duration: 10)
        #expect(range?.start == 2)
        #expect(range?.end == 8)
    }

    @Test func rangeIsClampedAndEmptyRangeIsRejected() {
        let clamped = TrimRange.resolve(start: -3, end: 50, duration: 10)
        #expect(clamped == nil)
        #expect(TrimRange.resolve(start: 5, end: 5.01, duration: 10) == nil)
    }
}
