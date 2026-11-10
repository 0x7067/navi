import CoreGraphics
import Testing

@testable import NaviCapture

/// The text tool and the one-key tool shortcuts in the markup editor.
@MainActor
@Suite struct AnnotateTextTests {
    private func makeModel() throws -> AnnotateModel {
        let context = try #require(CGContext(
            data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        return AnnotateModel(base: image, scale: 1)
    }

    private func click(_ model: AnnotateModel, at point: CGPoint) {
        model.pointerDown(at: point)
        model.pointerUp(from: point, to: point)
    }

    private func type(_ text: String, at point: CGPoint, in model: AnnotateModel) {
        model.tool = .text
        click(model, at: point)
        model.textEdit?.text = text
    }

    @Test func clickingAwayKeepsTheTextAndSelectsItWithThePointer() throws {
        let model = try makeModel()
        type("Hello", at: CGPoint(x: 50, y: 50), in: model)
        click(model, at: CGPoint(x: 300, y: 250))
        #expect(model.textEdit == nil)
        #expect(model.tool == .select)
        let mark = try #require(model.document.annotations.last)
        #expect(mark.text == "Hello")
        #expect(model.selection == mark.id)
    }

    @Test func emptyTextBoxMovesToTheNextClick() throws {
        let model = try makeModel()
        model.tool = .text
        click(model, at: CGPoint(x: 50, y: 50))
        click(model, at: CGPoint(x: 200, y: 100))
        #expect(model.textEdit?.point == CGPoint(x: 200, y: 100))
        #expect(model.document.annotations.isEmpty)
    }

    @Test func textCanBeDraggedWithTheTextTool() throws {
        let model = try makeModel()
        type("Drag me", at: CGPoint(x: 50, y: 50), in: model)
        model.finishText()
        model.tool = .text
        let mark = try #require(model.document.annotations.last)
        let grab = CGPoint(x: mark.bounds.midX, y: mark.bounds.midY)
        let drop = CGPoint(x: grab.x + 100, y: grab.y + 60)
        model.pointerDown(at: grab)
        model.pointerDragged(from: grab, to: drop)
        model.pointerUp(from: grab, to: drop)
        let moved = try #require(model.document.annotations.first { $0.id == mark.id })
        #expect(moved.start == CGPoint(x: mark.start.x + 100, y: mark.start.y + 60))
        #expect(model.textEdit == nil)
        #expect(model.tool == .select)
    }

    @Test func clickingSelectedTextEditsIt() throws {
        let model = try makeModel()
        type("Edit me", at: CGPoint(x: 50, y: 50), in: model)
        model.finishText()
        let mark = try #require(model.document.annotations.last)
        #expect(model.selection == mark.id)
        click(model, at: CGPoint(x: mark.bounds.midX, y: mark.bounds.midY))
        #expect(model.textEdit?.id == mark.id)
        #expect(model.textEdit?.text == "Edit me")
    }

    @Test func everyToolHasItsOwnKey() {
        let keys = AnnotationTool.allCases.map(\.shortcut)
        #expect(Set(keys).count == keys.count)
        for tool in AnnotationTool.allCases {
            #expect(AnnotationTool.forShortcut(String(tool.shortcut)) == tool)
            #expect(AnnotationTool.forShortcut(String(tool.shortcut).uppercased()) == tool)
        }
        #expect(AnnotationTool.forShortcut("z") == nil)
        #expect(AnnotationTool.forShortcut("ab") == nil)
    }

    /// The text must not change look when the box closes: the preview while typing is the same
    /// mark that gets saved.
    @Test func typedTextLooksTheSameBeforeAndAfterCommit() throws {
        let model = try makeModel()
        type("Same", at: CGPoint(x: 40, y: 60), in: model)
        let preview = try #require(model.textPreview)
        model.finishText()
        let saved = try #require(model.document.annotations.last)
        #expect(saved.start == preview.start)
        #expect(saved.fontSize == preview.fontSize)
        #expect(saved.color == preview.color)
        #expect(saved.text == preview.text)
        #expect(model.textPreview == nil)
    }
}
