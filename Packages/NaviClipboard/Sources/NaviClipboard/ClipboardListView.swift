import NaviCore
import SwiftUI

/// The history panel, styled like a macOS menu: search header, item rows, and a footer with actions.
/// Keyboard keys (arrows, Return, Esc, shortcuts) are handled by `ClipboardPanelController`.
struct ClipboardListView: View {
    @Bindable var model: ClipboardModel
    let onChoose: (CaptureItem) -> Void
    let onQuit: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        let results = model.results
        VStack(spacing: 0) {
            header
            list(results)
                .frame(height: model.listHeight(for: results))
            footer
        }
        .frame(width: Metrics.width, height: model.contentHeight, alignment: .top)
        .font(.system(size: 13))
        .onAppear { searchFocused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Navi")
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("type to search...", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 14)
        .frame(height: Metrics.headerHeight)
    }

    @ViewBuilder
    private func list(_ results: [CaptureItem]) -> some View {
        if results.isEmpty {
            Text(model.query.isEmpty ? "Copy something to start." : "No matches.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            ClipboardRow(model: model, item: item, index: index)
                            .frame(height: Metrics.rowHeight(for: item))
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onHover { inside in if inside { model.hover(index) } }
                            .onTapGesture { onChoose(item) }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                                model.rowFrames[item.id] = frame
                            }
                        }
                    }
                    .padding(Metrics.listPadding)
                }
                .scrollIndicators(.never)
                .background(SelectionFollower(model: model, ids: results.map(\.id), proxy: proxy))
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 10)
            FooterRow(title: "Clear", shortcut: "⌥⌘⌫") { model.clear() }
            FooterRow(title: "Quit", shortcut: "⌘Q", action: onQuit)
        }
        .padding(.vertical, Metrics.listPadding)
        .padding(.horizontal, Metrics.listPadding)
    }
}

/// Scrolls to the selected row when the keyboard moved it. It reads the selection here, so a selection
/// change redraws this view and the rows, not the whole list.
private struct SelectionFollower: View {
    let model: ClipboardModel
    let ids: [UUID]
    let proxy: ScrollViewProxy

    var body: some View {
        Color.clear.onChange(of: model.selection) { _, selection in
            if !model.selectedByHover, ids.indices.contains(selection) { proxy.scrollTo(ids[selection]) }
        }
    }
}

private struct ClipboardRow: View {
    let model: ClipboardModel
    let item: CaptureItem
    let index: Int
    @State private var loaded: NSImage?

    var body: some View {
        let isSelected = model.selection == index
        HStack(spacing: 6) {
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            }
            content
            Spacer(minLength: 12)
            if index < 9 {
                Text("⌘ \(index + 1)")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            }
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .task(id: item.contentHash) {
            if item.fileName != nil { loaded = await model.thumbnail(for: item) }
        }
    }

    @ViewBuilder private var content: some View {
        if item.fileName != nil {
            // Empty until the thumbnail is decoded in the background.
            if let image = model.cachedThumbnail(for: item) ?? loaded {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200, maxHeight: Metrics.imageRowHeight - 10, alignment: .leading)
            }
        } else {
            Text(Self.preview(item.text ?? ""))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// One line of text. Line breaks show as ⏎, like Maccy.
    static func preview(_ text: String) -> String {
        String(text.prefix(400))
            .replacingOccurrences(of: "\r\n", with: "⏎")
            .replacingOccurrences(of: "\n", with: "⏎")
            .replacingOccurrences(of: "\t", with: " ")
    }
}

private struct FooterRow: View {
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(shortcut).foregroundStyle(hovering ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        }
        .padding(.horizontal, 10)
        .frame(height: Metrics.footerRowHeight)
        .foregroundStyle(hovering ? Color.white : Color.primary)
        .background(hovering ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
    }
}

/// The detail card shown next to the selected row: full content, source app, times, and copy count.
struct ClipboardPreview: View {
    let item: CaptureItem
    let image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 480, maxHeight: 360, alignment: .leading)
            } else {
                Text(String((item.text ?? "").prefix(3000)))
                    .lineLimit(24)
                    .frame(maxWidth: 480, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                if let app = item.sourceApp {
                    HStack(spacing: 4) {
                        Text("Application:")
                        if let icon = appIcon {
                            Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                        }
                        Text(app)
                    }
                }
                Text("First copy time: \(item.createdAt.formatted(date: .long, time: .shortened))")
                Text("Last copy time: \(item.lastUsedAt.formatted(date: .long, time: .shortened))")
                Text("Number of copies: \(item.copyCount)")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Press ⌥P to (un)pin.")
                Text("Press ⌥⌫ to delete.")
            }
        }
        .font(.system(size: 13))
        .padding(16)
        .fixedSize()
    }

    private var appIcon: NSImage? {
        guard let bundleID = item.sourceBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
