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
    private var keyMonitor: Any?
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
        let fit = min(1, (visible.width * 0.85) / image.width, (visible.height * 0.85 - 100) / image.height)
        let size = CGSize(width: max(760, image.width * fit), height: max(420, image.height * fit + 100))
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
        watchKeys()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        guard let flat = model.flatten() else { return }
        onDone(Result(flat: flat, base: model.base, document: model.document, pointSize: model.pointSize))
        window?.close()
    }

    /// ⌘Z undo, ⇧⌘Z redo, and Delete for the selected mark. A local key monitor works even
    /// though Navi has no Edit menu. While text is being typed, the text field keeps these keys.
    private func watchKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let windowNumber = event.windowNumber
            let key = event.charactersIgnoringModifiers?.lowercased()
            let code = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.function, .numericPad, .capsLock])
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, let window = self.window, window.windowNumber == windowNumber,
                      self.model.textEdit == nil
                else { return false }
                if key == "z", flags == .command { self.model.undo(); return true }
                if key == "z", flags == [.command, .shift] { self.model.redo(); return true }
                // 51 is Delete (backspace), 117 is Forward Delete.
                if code == 51 || code == 117, flags.isEmpty, self.model.selection != nil {
                    self.model.deleteSelection()
                    return true
                }
                return false
            }
            return handled ? nil : event
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
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

    /// One row when the window is wide enough. Otherwise two rows: tools on top, then style,
    /// undo, and the actions. Nothing squishes or hides.
    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                toolGroups
                styleGroup
                historyGroup
                Spacer(minLength: 16)
                actions
            }
            // Narrow: tools and the actions on top, style and undo below.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    toolGroups
                    Spacer(minLength: 16)
                    actions
                }
                HStack(spacing: 10) {
                    styleGroup
                    historyGroup
                }
            }
            // Very narrow: the actions get their own row.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) { toolGroups }
                HStack(spacing: 10) {
                    styleGroup
                    historyGroup
                    Spacer(minLength: 16)
                    actions
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .padding(.leading, 66) // room for the window buttons
    }

    @ViewBuilder private var toolGroups: some View {
        ToolGroup { ForEach(Self.drawingTools, id: \.self, content: toolButton) }
        ToolGroup { ForEach(Self.effectTools, id: \.self, content: toolButton) }
    }

    private var styleGroup: some View {
        ToolGroup {
            ColorWell(model: model)
            ForEach(StrokeSize.allCases, id: \.self) { size in
                IconButton(isOn: model.strokeSize == size, style: .subtle, help: "Line: \(size.title)") {
                    model.strokeSize = size
                } label: {
                    Capsule().frame(width: 14, height: size.previewHeight)
                }
            }
            Menu {
                Button("Rotate Left") { model.apply(.rotateCounterclockwise) }
                Button("Rotate Right") { model.apply(.rotateClockwise) }
                Button("Flip Horizontal") { model.apply(.flipHorizontal) }
                Button("Flip Vertical") { model.apply(.flipVertical) }
                Divider()
                ForEach([0.5, 0.75, 1.5, 2], id: \.self) { factor in
                    Button("Resize to \(Int(factor * 100))%") { model.apply(.resize(factor)) }
                }
            } label: {
                Image(systemName: "rotate.right").frame(width: 28, height: 26).contentShape(Rectangle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Rotate, flip, resize")
        }
    }

    private var historyGroup: some View {
        ToolGroup {
            IconButton(help: "Undo (⌘Z)", action: model.undo) { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
            IconButton(help: "Redo (⇧⌘Z)", action: model.redo) { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            dragMe
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
            Button("Done", action: onDone)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .fixedSize()
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        IconButton(isOn: model.tool == tool, help: tool.help) { model.tool = tool } label: {
            Image(systemName: tool.symbol)
        }
    }

    /// A small picture of the marked-up shot. Drag it into any app to drop the image there.
    private var dragMe: some View {
        Group {
            if let image = model.rendered {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.primary.opacity(0.08)
            }
        }
            .frame(width: 36, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
            .contentShape(Rectangle())
            .onHover { inside in (inside ? NSCursor.openHand : NSCursor.arrow).set() }
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
            .help("Drag into any app")
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
                if let mark = model.selectedMark, model.cropRect == nil {
                    SelectionOverlay(mark: mark, fit: fit)
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
            .onContinuousHover { phase in
                switch phase {
                case let .active(location): model.cursor(at: pixel(location, fit: fit)).set()
                case .ended: NSCursor.arrow.set()
                }
            }
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
            .onSubmit(model.finishText)
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

// MARK: - Toolbar parts

/// A rounded group of toolbar buttons.
private struct ToolGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 1) { content }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
            .fixedSize()
    }
}

/// A 28 × 26 icon button. `isOn` shows it selected.
private struct IconButton<Label: View>: View {
    enum Style { case accent, subtle }

    var isOn = false
    var style = Style.accent
    let help: String
    let action: () -> Void
    @ViewBuilder var label: Label
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 26)
                .foregroundStyle(foreground)
                .background(RoundedRectangle(cornerRadius: 7).fill(background))
                .contentShape(Rectangle())
        }
        .onHover { isHovered = $0 }
        .help(help)
    }

    private var foreground: Color {
        if isOn { return style == .accent ? .white : .primary }
        return .primary.opacity(isEnabled ? 0.85 : 0.3)
    }

    private var background: Color {
        if isOn { return style == .accent ? .accentColor : .primary.opacity(0.16) }
        return .primary.opacity(isHovered && isEnabled ? 0.08 : 0)
    }
}

/// A round swatch of the current color. Click for preset colors, any color, or the screen sampler.
private struct ColorWell: View {
    @Bindable var model: AnnotateModel
    @State private var isOpen = false

    static let presets: [RGBA] = [
        .red,
        RGBA(red: 1, green: 0.58, blue: 0),
        RGBA(red: 1, green: 0.8, blue: 0),
        RGBA(red: 0.2, green: 0.78, blue: 0.35),
        RGBA(red: 0, green: 0.48, blue: 1),
        RGBA(red: 0.69, green: 0.32, blue: 0.87),
        RGBA(red: 1, green: 1, blue: 1),
        RGBA(red: 0, green: 0, blue: 0),
    ]

    var body: some View {
        Button { isOpen.toggle() } label: {
            Circle()
                .fill(model.color.swiftUI)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                .frame(width: 16, height: 16)
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .help("Color")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) { palette }
    }

    private var palette: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 4), spacing: 8) {
                ForEach(Self.presets, id: \.self) { color in
                    Button { model.color = color; isOpen = false } label: {
                        Circle()
                            .fill(color.swiftUI)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3)
                                .opacity(model.color == color ? 1 : 0))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            HStack {
                ColorPicker("More…", selection: Binding(
                    get: { model.color.swiftUI },
                    set: { color in
                        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                        model.color = RGBA(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
                    }
                ), supportsOpacity: false)
                Spacer()
                Button {
                    isOpen = false
                    let model = model
                    NSColorSampler().show { picked in
                        guard let rgb = picked?.usingColorSpace(.sRGB) else { return }
                        let color = RGBA(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
                        Task { @MainActor in model.color = color }
                    }
                } label: { Image(systemName: "eyedropper") }
                    .help("Pick a color from the screen")
            }
            .font(.callout)
        }
        .padding(12)
        .frame(width: 152)
    }
}

/// The selected mark's dashed outline and handles, drawn at screen size so they stay easy
/// to see and grab at any zoom.
private struct SelectionOverlay: View {
    let mark: Annotation
    let fit: CGFloat

    var body: some View {
        let lineGap = mark.isBox ? CGFloat(mark.lineWidth) / 2 * fit + 3 : 6
        let outline = (mark.isBox ? mark.box : mark.bounds)
            .applying(CGAffineTransform(scaleX: fit, y: fit))
            .insetBy(dx: -lineGap, dy: -lineGap)
        ZStack(alignment: .topLeading) {
            if mark.kind != .arrow, mark.kind != .line {
                Rectangle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    .frame(width: outline.width, height: outline.height)
                    .offset(x: outline.minX, y: outline.minY)
                Rectangle()
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: outline.width, height: outline.height)
                    .offset(x: outline.minX, y: outline.minY)
            }
            ForEach(mark.handles, id: \.self) { handle in
                let point = handlePoint(handle, outline: outline)
                let size: CGFloat = handle.isEdge ? 7 : 9
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                    .frame(width: size, height: size)
                    .offset(x: point.x - size / 2, y: point.y - size / 2)
            }
        }
        .allowsHitTesting(false)
    }

    /// Box handles sit on the dashed outline. Line and arrow handles sit on the ends.
    private func handlePoint(_ handle: Annotation.Handle, outline: CGRect) -> CGPoint {
        guard mark.isBox else {
            let point = mark.point(of: handle)
            return CGPoint(x: point.x * fit, y: point.y * fit)
        }
        let mark = mark.point(of: handle)
        let box = self.mark.box
        let x = mark.x < box.midX - 0.5 ? outline.minX : (mark.x > box.midX + 0.5 ? outline.maxX : outline.midX)
        let y = mark.y < box.midY - 0.5 ? outline.minY : (mark.y > box.midY + 0.5 ? outline.maxY : outline.midY)
        return CGPoint(x: x, y: y)
    }
}

private extension RGBA {
    var swiftUI: Color { Color(.sRGB, red: red, green: green, blue: blue) }
}

private extension StrokeSize {
    var previewHeight: CGFloat {
        switch self {
        case .small: 1.5
        case .medium: 3
        case .large: 5
        }
    }
}
