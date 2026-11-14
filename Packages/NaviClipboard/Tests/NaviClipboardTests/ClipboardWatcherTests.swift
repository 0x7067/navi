import AppKit
import Foundation
import NaviCore
import Testing
@testable import NaviClipboard

@MainActor
final class ClipboardWatcherTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "NaviClipboardTests-\(UUID().uuidString)")
    let pasteboard = NSPasteboard(name: .init("navi-test-\(UUID().uuidString)"))
    lazy var inbox = Inbox(directory: directory)

    isolated deinit {
        inbox.flush()
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func savesACopy() {
        let watcher = ClipboardWatcher(inbox: inbox, pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)
        watcher.check()
        #expect(inbox.items.map(\.text) == ["hello"])
    }

    @Test func savesAFinderFileCopyAsFilesAndPastesThem() throws {
        let watcher = ClipboardWatcher(inbox: inbox, pasteboard: pasteboard)
        let file = URL(filePath: "/tmp/navi report.pdf")
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        pasteboard.setString("navi report.pdf", forType: .string)
        pasteboard.setData(Self.png, forType: .tiff)
        watcher.check()
        let item = try #require(inbox.items.first)
        #expect(item.kind == .file && item.text == file.path)

        _ = Paster.write(item, inbox: inbox, to: pasteboard)
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        #expect(urls == [file])
    }

    @Test func savesAnImageWithPlainTextAsAnImage() throws {
        let watcher = ClipboardWatcher(inbox: inbox, pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setData(Self.png, forType: .png)
        pasteboard.setString("/Users/me/Desktop/screenshot.png", forType: .string)
        watcher.check()
        #expect(inbox.items.map(\.kind) == [.image])
    }

    @Test func savesRichTextWithAPictureAsText() {
        let watcher = ClipboardWatcher(inbox: inbox, pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("A1\tB1", forType: .string)
        pasteboard.setString("<table><tr><td>A1</td><td>B1</td></tr></table>", forType: .html)
        pasteboard.setData(Self.png, forType: .png)
        watcher.check()
        #expect(inbox.items.map(\.text) == ["A1\tB1"])
    }

    @Test func pastesRichTextWithItsFormattingAndAppTypes() throws {
        let watcher = ClipboardWatcher(inbox: inbox, pasteboard: pasteboard)
        let custom = NSPasteboard.PasteboardType("com.example.cells")
        pasteboard.clearContents()
        pasteboard.setString("bold", forType: .string)
        pasteboard.setString("<b>bold</b>", forType: .html)
        pasteboard.setData(Data([1, 2, 3]), forType: custom)
        watcher.check()
        let item = try #require(inbox.items.first)

        _ = Paster.write(item, inbox: inbox, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "bold")
        #expect(pasteboard.string(forType: .html) == "<b>bold</b>")
        #expect(pasteboard.data(forType: custom) == Data([1, 2, 3]))
    }

    @Test func pastesAnImageWithTheTextThatCameWithIt() throws {
        let watcher = ClipboardWatcher(inbox: inbox, pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setData(Self.png, forType: .png)
        pasteboard.setString("/Users/me/Desktop/screenshot.png", forType: .string)
        watcher.check()
        let item = try #require(inbox.items.first)

        _ = Paster.write(item, inbox: inbox, to: pasteboard)
        #expect(pasteboard.data(forType: .png) == Self.png)
        #expect(pasteboard.string(forType: .string) == "/Users/me/Desktop/screenshot.png")
    }

    static let png: Data = {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        return rep.representation(using: .png, properties: [:])!
    }()

    @Test func skipsWhatNaviWroteItself() {
        let watcher = ClipboardWatcher(inbox: inbox, pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("restored", forType: .string)
        pasteboard.setData(Data(), forType: NaviPasteboard.ownType)
        watcher.check()
        #expect(inbox.items.isEmpty)
    }
}
