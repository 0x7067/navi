# Navi

A Mac menu bar app for capture: clipboard history, screenshots with markup,
talk to type, and screen recording. Every capture goes into one shared history.

Status: clipboard history works. The other features are not built yet.

## Layout

| Path | Holds |
|---|---|
| `App/` | The app target: menu bar icon, global hotkey, wiring |
| `Packages/NaviCore` | Shared core: `Inbox` (history store), `CaptureItem`, `HotKey` |
| `Packages/NaviClipboard` | Clipboard history: pasteboard watcher, picker panel, paste |

Features talk to each other only through `NaviCore`.

## Build and run

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Navi.xcodeproj -scheme Navi -derivedDataPath build build
open build/Build/Products/Debug/Navi.app
```

Or run `xcodegen generate` and open `Navi.xcodeproj` in Xcode.

Unit tests: `cd Packages/NaviCore && swift test`

## Clipboard history

- `⇧⌘V` opens the history at the mouse. Opening Navi again (Spotlight, Finder) also opens it.
- Type to filter. Up and Down to move. Return to paste.
- `⌘1` to `⌘9` paste the first nine items.
- `⌥P` pins or unpins. Pinned items stay at the top and are never trimmed.
- `⌥⌫` deletes. `⌥⌘⌫` clears all unpinned items. Esc closes.
- Stay on a row to see a preview card: full content, source app, copy times, and copy count.

Paste needs the Accessibility permission (System Settings > Privacy & Security >
Accessibility). Without it, Navi copies the item but does not paste it.

Navi skips copies that password managers mark as private
([nspasteboard.org](http://nspasteboard.org) types).

History lives in `~/Library/Application Support/Navi/`. The newest 200 unpinned items are kept.
