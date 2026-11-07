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
        didSet { recolorSelection() }
    }

    var strokeSize: StrokeSize = .medium
    private(set) var selection: UUID?
    private(set) var cropRect: CGRect?
    var textEdit: TextEdit?
    private(set) var rendered: CGImage?

    @ObservationIgnored private var undoStack = UndoStack<Snapshot>()
    @ObservationIgnored private let renderer = AnnotationRenderer()
    @ObservationIgnored private var draft: Annotation?
    @ObservationIgnored private var dragOrigin: Annotation?

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
        commitText()
        switch tool {
        case .select:
            if let hit = document.hit(point, tolerance: 6 * scale) {
                selection = hit.id
                dragOrigin = hit
                recordUndo()
            } else {
                selection = nil
            }
        case .crop:
            cropRect = CGRect(origin: point, size: .zero)
        case .text, .counter:
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
        switch tool {
        case .select:
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
        switch tool {
        case .select:
            dragOrigin = nil
        case .crop:
            if !moved { cropRect = nil }
        case .text:
            if let hit = document.hit(point, tolerance: 4 * scale), hit.kind == .text {
                textEdit = TextEdit(point: hit.start, text: hit.text ?? "", id: hit.id)
            } else {
                textEdit = TextEdit(point: point, text: "")
            }
        case .counter:
            recordUndo()
            document.annotations.append(Annotation(
                kind: .counter, start: point, end: point, color: color, lineWidth: 0,
                number: document.nextCounter, fontSize: fontSize
            ))
            document.nextCounter += 1
        default:
            if var mark = draft, moved || mark.kind == .pencil || mark.kind == .highlighter {
                mark.end = point
                recordUndo()
                document.annotations.append(mark)
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

    private func recolorSelection() {
        guard let selection, let index = document.annotations.firstIndex(where: { $0.id == selection }) else { return }
        recordUndo()
        document.annotations[index].color = color
        render()
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

    private func render() {
        var marks = document.annotations
        if let editing = textEdit?.id { marks.removeAll { $0.id == editing } }
        if let draft { marks.append(draft) }
        rendered = renderer.render(base: base, marks: marks, selection: selection)
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
