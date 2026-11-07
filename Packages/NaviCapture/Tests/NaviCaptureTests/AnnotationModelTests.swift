import CoreGraphics
import Foundation
import Testing

@testable import NaviCapture

@Suite struct AnnotationModelTests {
    private func box(_ rect: CGRect) -> Annotation {
        Annotation(
            kind: .rectangle, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), color: .red, lineWidth: 4
        )
    }

    @Test func hitFindsTheTopMark() {
        var document = AnnotationDocument()
        let lower = box(CGRect(x: 0, y: 0, width: 100, height: 100))
        let upper = box(CGRect(x: 50, y: 50, width: 100, height: 100))
        document.annotations = [lower, upper]
        #expect(document.hit(CGPoint(x: 60, y: 60), tolerance: 0)?.id == upper.id)
        #expect(document.hit(CGPoint(x: 10, y: 10), tolerance: 0)?.id == lower.id)
        #expect(document.hit(CGPoint(x: 300, y: 300), tolerance: 4) == nil)
    }

    @Test func rotatingClockwiseMovesPointsAndSwapsTheSize() {
        let (transform, size) = ImageEdit.rotateClockwise.transform(for: CGSize(width: 200, height: 100))
        #expect(size == CGSize(width: 100, height: 200))
        // The top-left corner goes to the top right.
        #expect(CGPoint(x: 0, y: 0).applying(transform) == CGPoint(x: 100, y: 0))
        #expect(CGPoint(x: 200, y: 0).applying(transform) == CGPoint(x: 100, y: 200))
    }

    @Test func rotatingBothWaysIsANoOp() {
        let original = CGSize(width: 200, height: 100)
        let (clockwise, rotated) = ImageEdit.rotateClockwise.transform(for: original)
        let (back, size) = ImageEdit.rotateCounterclockwise.transform(for: rotated)
        #expect(size == original)
        #expect(CGPoint(x: 30, y: 40).applying(clockwise).applying(back) == CGPoint(x: 30, y: 40))
    }

    @Test func flipAndCropAndResize() {
        let size = CGSize(width: 200, height: 100)
        #expect(CGPoint(x: 10, y: 20).applying(ImageEdit.flipHorizontal.transform(for: size).0) == CGPoint(x: 190, y: 20))
        #expect(CGPoint(x: 10, y: 20).applying(ImageEdit.flipVertical.transform(for: size).0) == CGPoint(x: 10, y: 80))
        let (crop, cropSize) = ImageEdit.crop(CGRect(x: 5, y: 10, width: 50, height: 40)).transform(for: size)
        #expect(cropSize == CGSize(width: 50, height: 40))
        #expect(CGPoint(x: 10, y: 20).applying(crop) == CGPoint(x: 5, y: 10))
        let (resize, half) = ImageEdit.resize(0.5).transform(for: size)
        #expect(half == CGSize(width: 100, height: 50))
        #expect(CGPoint(x: 10, y: 20).applying(resize) == CGPoint(x: 5, y: 10))
    }

    @Test func resizingScalesLineWidths() {
        var document = AnnotationDocument()
        document.annotations = [box(CGRect(x: 0, y: 0, width: 10, height: 10))]
        document.apply(CGAffineTransform(scaleX: 2, y: 2), scale: 2)
        #expect(document.annotations[0].lineWidth == 8)
        #expect(document.annotations[0].end == CGPoint(x: 20, y: 20))
    }

    @Test func documentRoundTripsThroughJSON() throws {
        var document = AnnotationDocument()
        var text = box(.zero)
        text.kind = .text
        text.text = "Hi"
        document.annotations = [text]
        document.nextCounter = 3
        let data = try JSONEncoder().encode(document)
        #expect(try JSONDecoder().decode(AnnotationDocument.self, from: data) == document)
    }

    @Test func undoAndRedo() {
        var stack = UndoStack<Int>()
        stack.record(1)
        stack.record(2)
        #expect(stack.undo(current: 3) == 2)
        #expect(stack.undo(current: 2) == 1)
        #expect(stack.undo(current: 1) == nil)
        #expect(stack.redo(current: 1) == 2)
        stack.record(2)
        #expect(!stack.canRedo)
    }
}

@Suite struct TextRecognizerTests {
    @Test func joinsLinesAndCodesWithoutDuplicates() {
        let text = TextRecognizer.joined(lines: ["Hello", "https://x.co"], payloads: ["https://x.co", "WIFI:S:home;"])
        #expect(text == "Hello\nhttps://x.co\nWIFI:S:home;")
    }
}
