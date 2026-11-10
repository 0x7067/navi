import AppKit
import Observation

/// Line widths in points. The editor multiplies by the image scale.
enum StrokeSize: Double, CaseIterable {
    case small = 2, medium = 4, large = 8

    var title: String {
        switch self {
        case .small: "Thin"
        case .medium: "Medium"
        case .large: "Thick"
        }
    }
}

/// The state of one markup editor: base image, marks, tool, selection, and undo.
@MainActor
@Observable
final class AnnotateModel {
    struct Snapshot {
        let base: CGImage
        let document: AnnotationDocument
    }

    /// Text that is being typed. `id` is set when an old text mark is being changed.
    struct TextEdit {
        var point: CGPoint
        var text: String
        var id: UUID?
    }

    private(set) var base: CGImage
    private(set) var document: AnnotationDocument
    /// Pixels per point of the capture (2 on Retina).
    let scale: CGFloat
    var tool: AnnotationTool = .arrow {
        didSet {
            if tool != .select { selection = nil }
            if tool != .crop { cropRect = nil }
            commitText()
            render()
        }
    }

    var color: RGBA = .red {
        didSet { if !isSyncingStyle { restyleSelection() } }
    }

    var strokeSize: StrokeSize = .medium {
        didSet { if !isSyncingStyle { restyleSelection() } }
    }

    /// The selected mark. It shows handles, and the color and size pickers change it.
    private(set) var selection: UUID? {
        didSet { syncStyleToSelection() }
    }
    private(set) var cropRect: CGRect?
    var textEdit: TextEdit? {
        didSet { render() }
    }
    private(set) var rendered: CGImage?

    private var undoStack = UndoStack<Snapshot>()
    @ObservationIgnored private let renderer = AnnotationRenderer()
    @ObservationIgnored private var draft: Annotation?
    @ObservationIgnored private var dragOrigin: Annotation?
    /// The handle being dragged on the selected mark.
    @ObservationIgnored private var resizing: Annotation.Handle?
    /// True while the pickers copy the selected mark's style, so that copy does not change the mark.
    @ObservationIgnored private var isSyncingStyle = false
    /// A text mark that was already selected when the pointer went down. A click without a drag edits it.
    @ObservationIgnored private var clickedSelectedText: UUID?

    var canUndo: Bool { undoStack.canUndo }
    var canRedo: Bool { undoStack.canRedo }
    var pixelSize: CGSize { CGSize(width: base.width, height: base.height) }
    var pointSize: CGSize { CGSize(width: CGFloat(base.width) / scale, height: CGFloat(base.height) / scale) }

    init(base: CGImage, document: AnnotationDocument = AnnotationDocument(), scale: CGFloat) {
        self.base = base
        self.document = document
        self.scale = max(scale, 1)
        render()
    }

    // MARK: Pointer input, in image pixels

    func pointerDown(at point: CGPoint) {
        clickedSelectedText = nil
        // A click outside the text box ends typing. Like other marks, the new text is then selected
        // with the pointer tool, so it can be dragged at once. The click does nothing else.
        if let edit = textEdit, edit.id != nil || !edit.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           document.hit(point, tolerance: 4 * scale)?.kind != .text {
            finishText()
            render()
            return
        }
        commitText()
        // A handle on the selected mark resizes it, whatever the tool.
        if let selected = selectedMark, let handle = selected.handle(at: point, tolerance: 10 * scale) {
            resizing = handle
            dragOrigin = selected
            recordUndo()
            return
        }
        if tool != .select { selection = nil }
        switch tool {
        case .select:
            if let hit = document.hit(point, tolerance: 6 * scale) {
                if hit.kind == .text, hit.id == selection { clickedSelectedText = hit.id }
                selection = hit.id
                dragOrigin = hit
                recordUndo()
            } else {
                selection = nil
            }
        case .crop:
            cropRect = CGRect(origin: point, size: .zero)
        case .text:
            // Press on a text mark to drag it. A click without a drag edits it (see `pointerUp`).
            if let hit = document.hit(point, tolerance: 4 * scale), hit.kind == .text {
                selection = hit.id
                dragOrigin = hit
                recordUndo()
            }
        case .counter:
            break
        default:
            guard let kind = Annotation.Kind(rawValue: tool.rawValue) else { return }
            draft = Annotation(
                kind: kind, start: point, end: point, points: [point], color: color,
                lineWidth: strokeSize.rawValue * scale, fontSize: fontSize
            )
        }
        render()
    }

    func pointerDragged(from start: CGPoint, to point: CGPoint) {
        if let handle = resizing, let origin = dragOrigin,
           let index = document.annotations.firstIndex(where: { $0.id == origin.id }) {
            document.annotations[index] = origin.resized(handle, to: point)
            render()
            return
        }
        switch tool {
        case .select, .text:
            guard let origin = dragOrigin, let index = document.annotations.firstIndex(where: { $0.id == origin.id }) else { return }
            document.annotations[index] = origin.moved(by: CGVector(dx: point.x - start.x, dy: point.y - start.y))
        case .crop:
            cropRect = CaptureGeometry.rect(from: start, to: point).intersection(CGRect(origin: .zero, size: pixelSize))
        default:
            draft?.end = point
            draft?.points.append(point)
        }
        render()
    }

    func pointerUp(from start: CGPoint, to point: CGPoint) {
        let moved = hypot(point.x - start.x, point.y - start.y) > 3 * scale
        if resizing != nil {
            resizing = nil
            dragOrigin = nil
            render()
            return
        }
        switch tool {
        case .select:
            dragOrigin = nil
            if !moved, let id = clickedSelectedText, let mark = document.annotations.first(where: { $0.id == id }) {
                textEdit = TextEdit(point: mark.start, text: mark.text ?? "", id: id)
            }
            clickedSelectedText = nil
        case .crop:
            if !moved { cropRect = nil }
        case .text:
            if let origin = dragOrigin {
                dragOrigin = nil
                if moved {
                    // Dragged a text mark: keep it selected with the pointer tool.
                    tool = .select
                    selection = origin.id
                } else if let mark = document.annotations.first(where: { $0.id == origin.id }) {
                    textEdit = TextEdit(point: mark.start, text: mark.text ?? "", id: mark.id)
                }
            } else {
                textEdit = TextEdit(point: point, text: "")
            }
        case .counter:
            recordUndo()
            let counter = Annotation(
                kind: .counter, start: point, end: point, color: color, lineWidth: 0,
                number: document.nextCounter, fontSize: fontSize
            )
            document.annotations.append(counter)
            document.nextCounter += 1
            // The counter tool stays on, so you can click the next step.
            selection = counter.id
        default:
            if var mark = draft, moved || mark.kind == .pencil || mark.kind == .highlighter {
                mark.end = point
                recordUndo()
                document.annotations.append(mark)
                // Back to the pointer, with the new mark selected: its handles show and the pickers change it.
                tool = .select
                selection = mark.id
            }
            draft = nil
        }
        render()
    }

    // MARK: Commands

    func deleteSelection() {
        guard let selection else { return }
        recordUndo()
        document.annotations.removeAll { $0.id == selection }
        self.selection = nil
        render()
    }

    func commitText() {
        guard let edit = textEdit else { return }
        textEdit = nil
        let text = edit.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = edit.id, let index = document.annotations.firstIndex(where: { $0.id == id }) {
            recordUndo()
            if text.isEmpty { document.annotations.remove(at: index) } else { document.annotations[index].text = text }
        } else if !text.isEmpty {
            recordUndo()
            document.annotations.append(Annotation(
                kind: .text, start: edit.point, end: edit.point, color: color, lineWidth: 0, text: text, fontSize: fontSize
            ))
        }
        render()
    }

    /// Return in the text box: keep the text, then go back to the pointer with it selected.
    func finishText() {
        let editedID = textEdit?.id
        let count = document.annotations.count
        commitText()
        let id = editedID ?? (document.annotations.count > count ? document.annotations.last?.id : nil)
        guard let id, document.annotations.contains(where: { $0.id == id }) else { return }
        tool = .select
        selection = id
        render()
    }

    /// The pointer for a spot on the image: resize arrows over a handle, a hand over a mark
    /// you can move, a crosshair for drawing.
    func cursor(at point: CGPoint) -> NSCursor {
        if let mark = selectedMark, let handle = mark.handle(at: point, tolerance: 10 * scale) {
            return Self.resizeCursor(handle, of: mark)
        }
        switch tool {
        case .select:
            return document.hit(point, tolerance: 6 * scale) == nil ? .arrow : .openHand
        case .text:
            return .iBeam
        default:
            return .crosshair
        }
    }

    private static func resizeCursor(_ handle: Annotation.Handle, of mark: Annotation) -> NSCursor {
        switch handle {
        case .top: return .frameResize(position: .top, directions: .all)
        case .bottom: return .frameResize(position: .bottom, directions: .all)
        case .left: return .frameResize(position: .left, directions: .all)
        case .right: return .frameResize(position: .right, directions: .all)
        default:
            guard mark.isBox else { return .crosshair }
            let point = mark.point(of: handle)
            let box = mark.box
            let top = point.y <= box.midY, left = point.x <= box.midX
            let position: NSCursor.FrameResizePosition = switch (top, left) {
            case (true, true): .topLeft
            case (true, false): .topRight
            case (false, true): .bottomLeft
            case (false, false): .bottomRight
            }
            return .frameResize(position: position, directions: .all)
        }
    }

    func applyCrop() {
        guard let rect = cropRect, rect.width > 2, rect.height > 2 else { return }
        cropRect = nil
        apply(.crop(rect.integral))
    }

    func cancelCrop() {
        cropRect = nil
        render()
    }

    func apply(_ edit: ImageEdit) {
        commitText()
        guard let image = ImageOps.apply(edit, to: base) else { return }
        recordUndo()
        let (transform, _) = edit.transform(for: pixelSize)
        document.apply(transform, scale: edit.markScale)
        base = image
        render()
    }

    /// Places another image in the middle, at most half the size of the capture.
    func addImage(_ image: CGImage) {
        guard let png = ImageOps.png(image, pointSize: CGSize(width: image.width, height: image.height)) else { return }
        let fit = min(1, min(pixelSize.width / 2 / CGFloat(image.width), pixelSize.height / 2 / CGFloat(image.height)))
        let size = CGSize(width: CGFloat(image.width) * fit, height: CGFloat(image.height) * fit)
        let origin = CGPoint(x: (pixelSize.width - size.width) / 2, y: (pixelSize.height - size.height) / 2)
        recordUndo()
        var mark = Annotation(
            kind: .image, start: origin, end: CGPoint(x: origin.x + size.width, y: origin.y + size.height),
            color: color, lineWidth: 0
        )
        mark.imagePNG = png
        document.annotations.append(mark)
        tool = .select
        selection = mark.id
        render()
    }

    func undo() {
        commitText()
        guard let snapshot = undoStack.undo(current: Snapshot(base: base, document: document)) else { return }
        restore(snapshot)
    }

    func redo() {
        guard let snapshot = undoStack.redo(current: Snapshot(base: base, document: document)) else { return }
        restore(snapshot)
    }

    /// The final flat image, without selection outlines.
    func flatten() -> CGImage? {
        commitText()
        return renderer.render(base: base, marks: document.annotations)
    }

    // MARK: Private

    private var fontSize: Double { (8 + strokeSize.rawValue * 3) * scale }

    var selectedMark: Annotation? {
        guard let selection else { return nil }
        return document.annotations.first { $0.id == selection }
    }

    /// Gives the selected mark the picked color and size.
    private func restyleSelection() {
        guard let selection, let index = document.annotations.firstIndex(where: { $0.id == selection }) else { return }
        var mark = document.annotations[index]
        mark.color = color
        if mark.usesFontSize { mark.fontSize = fontSize } else if mark.lineWidth > 0 { mark.lineWidth = strokeSize.rawValue * scale }
        guard mark != document.annotations[index] else { return }
        recordUndo()
        document.annotations[index] = mark
        render()
    }

    /// Shows the selected mark's color and size in the pickers.
    private func syncStyleToSelection() {
        guard let mark = selectedMark else { return }
        isSyncingStyle = true
        defer { isSyncingStyle = false }
        if mark.kind != .image, mark.kind != .blur, mark.kind != .pixelate, mark.kind != .spotlight { color = mark.color }
        let size = mark.usesFontSize ? (mark.fontSize / scale - 8) / 3 : mark.lineWidth / scale
        if let nearest = StrokeSize.allCases.min(by: { abs($0.rawValue - size) < abs($1.rawValue - size) }), size > 0 {
            strokeSize = nearest
        }
    }

    private func recordUndo() {
        undoStack.record(Snapshot(base: base, document: document))
    }

    private func restore(_ snapshot: Snapshot) {
        base = snapshot.base
        document = snapshot.document
        selection = nil
        render()
    }

    /// The text being typed, drawn by the same renderer as finished text, so it looks the same
    /// before and after the box closes. Nil while the box is empty.
    var textPreview: Annotation? {
        guard let edit = textEdit, !edit.text.isEmpty else { return nil }
        let original = edit.id.flatMap { id in document.annotations.first { $0.id == id } }
        return Annotation(
            kind: .text, start: edit.point, end: edit.point, color: original?.color ?? color, lineWidth: 0,
            text: edit.text, fontSize: original?.fontSize ?? fontSize
        )
    }

    /// Font size, in image pixels, of the text being typed.
    var textEditFontSize: Double {
        let original = textEdit?.id.flatMap { id in document.annotations.first { $0.id == id } }
        return original?.fontSize ?? fontSize
    }

    private func render() {
        var marks = document.annotations
        if let editing = textEdit?.id { marks.removeAll { $0.id == editing } }
        if let preview = textPreview { marks.append(preview) }
        if let draft { marks.append(draft) }
        rendered = renderer.render(base: base, marks: marks)
    }
}

// MARK: - Saved markup

/// Saves and loads markup as a `.navi` folder: `document.json` plus `base.png`.
enum MarkupStore {
    static func save(base: CGImage, document: AnnotationDocument, to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(document).write(to: folder.appending(path: "document.json"), options: .atomic)
        guard let png = ImageOps.png(base, pointSize: CGSize(width: base.width, height: base.height)) else { return }
        try png.write(to: folder.appending(path: "base.png"), options: .atomic)
    }

    static func load(from folder: URL) -> (CGImage, AnnotationDocument)? {
        guard let json = try? Data(contentsOf: folder.appending(path: "document.json")),
              let document = try? JSONDecoder().decode(AnnotationDocument.self, from: json),
              let source = CGImageSourceCreateWithURL(folder.appending(path: "base.png") as CFURL, nil),
              let base = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return (base, document)
    }
}
