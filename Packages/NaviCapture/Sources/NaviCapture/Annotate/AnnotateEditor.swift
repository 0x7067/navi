import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The markup editor window. `onDone` gets the flat image, the base image, and the marks.
@MainActor
final class AnnotateEditor: NSObject, NSWindowDelegate {
    struct Result {
        let flat: CGImage
        let base: CGImage
        let document: AnnotationDocument
        let pointSize: CGSize
    }

    private let model: AnnotateModel
    private var window: NSWindow?
    private let onDone: (Result) -> Void
    private let onClose: () -> Void

    init(base: CGImage, document: AnnotationDocument, scale: CGFloat, onDone: @escaping (Result) -> Void, onClose: @escaping () -> Void) {
        model = AnnotateModel(base: base, document: document, scale: scale)
        self.onDone = onDone
        self.onClose = onClose
        super.init()
    }

    func show() {
        let visible = (NSScreen.underMouse ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let image = model.pointSize
        let fit = min(1, (visible.width * 0.85) / image.width, (visible.height * 0.85 - 60) / image.height)
        let size = CGSize(width: max(760, image.width * fit), height: max(420, image.height * fit + 60))
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Annotate"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: AnnotateView(
            model: model,
            onDone: { [weak self] in self?.finish() },
            onCancel: { [weak self] in self?.window?.close() }
        ))
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        guard let flat = model.flatten() else { return }
        onDone(Result(flat: flat, base: model.base, document: model.document, pointSize: model.pointSize))
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        onClose()
    }
}

struct AnnotateView: View {
    @Bindable var model: AnnotateModel
    let onDone: () -> Void
    let onCancel: () -> Void

    private static let drawingTools: [AnnotationTool] = [
        .select, .arrow, .rectangle, .filledRectangle, .ellipse, .line, .pencil, .highlighter, .text, .counter,
    ]
    private static let effectTools: [AnnotationTool] = [.blur, .pixelate, .spotlight, .crop]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
        }
        .frame(minWidth: 760, minHeight: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 2) {
            ForEach(Self.drawingTools, id: \.self, content: toolButton)
            Divider().frame(height: 20).padding(.horizontal, 4)
            ForEach(Self.effectTools, id: \.self, content: toolButton)
            Divider().frame(height: 20).padding(.horizontal, 4)
            ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .help("Color")
            Button {
                let model = model
                NSColorSampler().show { picked in
                    guard let rgb = picked?.usingColorSpace(.sRGB) else { return }
                    let color = RGBA(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
                    Task { @MainActor in model.color = color }
                }
            } label: { Image(systemName: "eyedropper") }
                .help("Pick a color from the screen")
            Picker("Size", selection: $model.strokeSize) {
                ForEach(StrokeSize.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 92)
            Menu {
                Button("Rotate Left") { model.apply(.rotateCounterclockwise) }
                Button("Rotate Right") { model.apply(.rotateClockwise) }
                Button("Flip Horizontal") { model.apply(.flipHorizontal) }
                Button("Flip Vertical") { model.apply(.flipVertical) }
                Divider()
                ForEach([0.5, 0.75, 1.5, 2], id: \.self) { factor in
                    Button("Resize to \(Int(factor * 100))%") { model.apply(.resize(factor)) }
                }
            } label: { Image(systemName: "rotate.right") }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Rotate, flip, resize")
            Divider().frame(height: 20).padding(.horizontal, 4)
            Button(action: model.undo) { Image(systemName: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo)
                .help("Undo")
            Button(action: model.redo) { Image(systemName: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo)
                .help("Redo")
            Button(action: model.deleteSelection) { EmptyView() }
                .keyboardShortcut(.delete, modifiers: [])
                .frame(width: 0)
                .opacity(0)
            Spacer(minLength: 8)
            dragMe
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Done", action: onDone)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .padding(.leading, 70) // room for the window buttons
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        Button { model.tool = tool } label: {
            Image(systemName: tool.symbol)
                .frame(width: 28, height: 26)
                .foregroundStyle(model.tool == tool ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 6).fill(model.tool == tool ? Color.accentColor : .clear))
                .contentShape(Rectangle())
        }
        .help(tool.title)
    }

    /// Drag this into any app to share the marked-up image.
    private var dragMe: some View {
        Label("Drag me", systemImage: "hand.draw")
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
            .onDrag {
                guard let flat = model.flatten(), let png = ImageOps.png(flat, pointSize: model.pointSize) else {
                    return NSItemProvider()
                }
                let folder = FileManager.default.temporaryDirectory.appending(path: "Navi/\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appending(path: CaptureGeometry.fileName(for: .now, fileExtension: "png"))
                try? png.write(to: url)
                let provider = NSItemProvider(object: url as NSURL)
                provider.suggestedName = url.deletingPathExtension().lastPathComponent
                return provider
            }
            .help("Drag the marked-up image into any app")
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(.sRGB, red: model.color.red, green: model.color.green, blue: model.color.blue) },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                model.color = RGBA(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
            }
        )
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { proxy in
            let pixels = model.pixelSize
            let fit = min(1 / model.scale, (proxy.size.width - 40) / pixels.width, (proxy.size.height - 40) / pixels.height)
            let shown = CGSize(width: pixels.width * fit, height: pixels.height * fit)
            ZStack(alignment: .topLeading) {
                if let image = model.rendered {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: shown.width, height: shown.height)
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                }
                if let crop = model.cropRect {
                    cropOverlay(crop, fit: fit, shown: shown)
                }
                if model.textEdit != nil {
                    textField(fit: fit)
                }
            }
            .frame(width: shown.width, height: shown.height)
            .contentShape(Rectangle())
            .gesture(drawGesture(fit: fit))
            .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
                loadDroppedImage(providers)
                return true
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.opacity(0.2))
    }

    private func drawGesture(fit: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = pixel(value.startLocation, fit: fit)
                let point = pixel(value.location, fit: fit)
                if value.translation == .zero {
                    model.pointerDown(at: start)
                } else {
                    model.pointerDragged(from: start, to: point)
                }
            }
            .onEnded { value in
                model.pointerUp(from: pixel(value.startLocation, fit: fit), to: pixel(value.location, fit: fit))
            }
    }

    private func pixel(_ point: CGPoint, fit: CGFloat) -> CGPoint {
        CGPoint(x: point.x / fit, y: point.y / fit)
    }

    private func cropOverlay(_ crop: CGRect, fit: CGFloat, shown: CGSize) -> some View {
        let rect = CGRect(x: crop.minX * fit, y: crop.minY * fit, width: crop.width * fit, height: crop.height * fit)
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: shown))
                path.addRect(rect)
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
            Rectangle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(.white)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
            HStack(spacing: 6) {
                Button("Cancel", action: model.cancelCrop)
                Button("Crop", action: model.applyCrop)
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
            .offset(x: rect.minX, y: min(rect.maxY + 6, shown.height - 26))
        }
    }

    private func textField(fit: CGFloat) -> some View {
        let point = model.textEdit?.point ?? .zero
        let fontSize = (8 + model.strokeSize.rawValue * 3) * model.scale * fit
        return TextField("Type", text: Binding(
            get: { model.textEdit?.text ?? "" },
            set: { model.textEdit?.text = $0 }
        ), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: max(12, fontSize), weight: .bold))
            .foregroundStyle(Color(.sRGB, red: model.color.red, green: model.color.green, blue: model.color.blue))
            .frame(minWidth: 120, maxWidth: 400, alignment: .leading)
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 1))
            .offset(x: point.x * fit, y: point.y * fit)
            .onSubmit(model.commitText)
    }

    private func loadDroppedImage(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSURL.self) {
                _ = provider.loadObject(ofClass: NSURL.self) { url, _ in
                    guard let url = url as? URL else { return }
                    Task { @MainActor in
                        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                        else { return }
                        model.addImage(image)
                    }
                }
                return
            }
        }
    }
}
