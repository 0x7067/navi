# Navi

A macOS menu bar app for capture. It combines four tools:

| Feature | Model app | Status |
|---|---|---|
| Clipboard history | Maccy | Done (v0.1) |
| Screenshot with markup | CleanShot X | Next. See the plan |
| Talk to type | Wispr Flow | Later |
| Screen recording | CleanShot X, then Screen Studio | Last |

The main idea: every capture (clip, screenshot, recording, GIF, dictated text,
OCR text) goes to one place. It shows first as a corner card, then in one shared
history list. `⇧⌘V` opens that list.

The name comes from the fairy in Zelda. Navi is a Nintendo name, so rename the
app before any public release.

## Plan

`docs/capture-plan.html` is the source of truth for screenshots and recording.
It has three tabs:

1. **Prototype:** a clickable HTML mock of every capture flow. Match its layout
   and behavior in the real app.
2. **Feature map:** every CleanShot X feature (launch video and features page),
   what Navi builds, the macOS API, and the step.
3. **Plan:** steps 1 to 5, what "done" means for each one, permissions, and
   open questions.

Build order: clipboard (done) → screenshots (steps 1–4) → talk to type →
recording (step 5).

**Next work: step 1, the capture core and the corner card.**

## Decisions

- **One app, one menu bar icon.** This gives one set of macOS permissions
  (screen, mic, accessibility) and one shared history.
- **One Swift package per feature** under `Packages/`. Features talk only
  through `NaviCore`. A feature package never imports another feature package.
- **Stack:** Swift 6, SwiftUI, and AppKit. Not Electron. Not Tauri.
- **Rust:** not for v1. Later it may be a small library for one engine part,
  such as speech or GIF encoding (gifski).
- **No cloud.** Everything stays local. Where CleanShot has a Cloud button,
  Navi shows "Show in Finder."
- **Two kinds of UI:**
  - *Quick pickers* for fast actions, such as the Maccy-style clipboard menu at
    the mouse. Fast in, fast out.
  - *Home window* in the style of Wispr Flow's main app. It brings all captures
    together. It is not for quick paste. Not built yet.
- **Hide desktop icons and mute notifications** do not change the real screen.
  Navi leaves Finder's desktop windows and Notification Center's windows out of
  the ScreenCaptureKit filter.
- **Single window capture** uses `SCContentFilter(desktopIndependentWindow:)`,
  so nothing behind the window gets in.

### Proposed defaults (confirm with Donovan before you build them)

- Navi takes over `⇧⌘3`, `⇧⌘4`, and `⇧⌘5`. The user turns off the macOS
  shortcuts in System Settings first.
- Captures save to `~/Pictures/Navi`.
- Corner cards do not close on their own. Close with ✕ or a swipe.

## UX to copy

- **Maccy (clipboard):** keyboard only. Hotkey, type to filter, Return to paste,
  `⌘1`–`⌘9`, `⌥P` pin, `⌥⌫` delete, `⌥⌘⌫` clear, a preview card beside the
  selected row. Line breaks show as `⏎`.
- **CleanShot X (capture):** crosshair with magnifier and pixel size, snap to
  windows, freeze screen. Corner card: on hover it blurs and shows round Copy and
  Save buttons. Corners: Pin (top left), Close (top right), Annotate or Trim
  (bottom left), Show in Finder (bottom right). Drag the card into any app.
  Markup: arrow, box, filled box, ellipse, line, pencil, highlighter, text,
  counter, blur, pixelate, spotlight, crop. Record bar: mic, options, exact
  width × height, fullscreen, then Record GIF or Record Video.
- **Wispr Flow (talk to type):** hold fn to talk, release to type at the
  cursor. Double-tap fn locks hands-free. A small pill at the bottom of the
  screen with a waveform. A cleanup pass removes filler words and adds
  punctuation. On-device Apple speech first, then a small model for cleanup.

Reference code to read, but **do not copy** (license): `sw33tLie/macshot`
(GPL-3.0) and `lzhgus/Capso` (BSL 1.1). Ideas to borrow: Shottr's pixel ruler,
Xnapper's backgrounds, and macshot's auto-redact.

## Layout

| Path | Holds |
|---|---|
| `project.yml` | XcodeGen spec. The `.xcodeproj` is generated and gitignored |
| `App/Sources/NaviApp.swift` | Menu bar icon, global hotkey, app wiring |
| `Packages/NaviCore` | `Inbox` (shared history store), `CaptureItem`, `HotKey` (Carbon global hotkeys) |
| `Packages/NaviClipboard` | Pasteboard watcher, Maccy-style panel, paste |
| `docs/capture-plan.html` | Prototype, feature map, and plan |

`Inbox` keeps items in `~/Library/Application Support/Navi/` (`history.json`
plus `files/`). Items sort by pinned, then by `lastUsedAt`. The newest 200
unpinned items stay. New fields on `CaptureItem` must decode from old history
files (use `decodeIfPresent` in `init(from:)`).

## Commands

```sh
xcodegen generate                       # after you change project.yml or add files
~/.local/bin/heavy -- xcodebuild -project Navi.xcodeproj -scheme Navi \
  -configuration Debug -derivedDataPath build -quiet build
cd Packages/NaviCore && swift test      # unit tests, run directly
pkill -x Navi; open build/Build/Products/Debug/Navi.app
```

Signing uses the Apple Development certificate, team `77SAW76597`, set in
`project.yml`. Keep a stable signature so macOS keeps the Accessibility and
Screen Recording permissions between builds.

## Rules

- `@MainActor` on UI and state types. Swift 6 strict concurrency must build
  with no warnings.
- Put pure logic in packages with unit tests (Swift Testing). Test `NaviCore`
  changes with `swift test`.
- After a UI change, build, run, and ask Donovan to check it. Your terminal
  cannot take screenshots of the real screen.
- Skip pasteboard items marked private by password managers (nspasteboard.org
  types).
- Update this file when a decision changes. Write the current state, not the
  history.

## Brain

The project note is `~/Developer/personal/personal-assistant/projects/navi.md`.
It keeps a short summary and status. Put details here, in the repo.
