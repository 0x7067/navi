# Navi

A macOS menu bar app for capture. It combines four tools:

| Feature | Model app | Status |
|---|---|---|
| Clipboard history | Maccy | Done (v0.1) |
| Screenshot with markup | CleanShot X | Steps 1–4 built. Step 1 checked |
| Talk to type | Wispr Flow | Built, not checked |
| Screen recording | CleanShot X, then Screen Studio | Step 5 built, not checked. No Screen Studio editor |

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

**Step 1 (capture core and corner card) is built and checked** (area, window,
fullscreen, Copy, Save, Show in Finder, drag, Close All, card shortcuts, Hide
Desktop Icons). Not checked yet: the `⌥⇧⌘N` menu and a second display.

**Steps 2–4 are built, not checked by Donovan yet:**
- Step 2, markup editor (`Annotate/`): every tool in the plan, color picker
  and screen color sampler, three line sizes, select/move/delete marks,
  rotate, flip, resize, crop, undo/redo, drop an image in to combine, "Drag
  me", Done updates the card and the history item. Marks stay editable in
  `<id>.navi` (JSON + base PNG) beside the Inbox file.
- Step 3 (`Extras/`): pin to screen (move, scroll to resize, opacity, lock so
  clicks go through, unlock from the menu), Capture Text (OCR + QR, Vision),
  self-timer, all-in-one bar on `⇧⌘5`, card quick actions (right-click).
- Step 4: scrolling capture (`Scroll/`, Vision registration, vertical and
  horizontal, Auto-scroll), background tool (`Background/`: gradients, solid,
  picture, padding, corners, shadow, aspect ratio, auto balance, presets).

**Talk to type and step 5 are built, not checked by Donovan yet:**
- `Packages/NaviDictation`: hold fn to talk, double-tap fn to lock, pill with
  a waveform, on-device speech (`SpeechAnalyzer`, fallback
  `SFSpeechRecognizer`), cleanup with Foundation Models or rules, paste at the
  cursor, then the old clipboard comes back. fn with another key (fn+⌫,
  fn+arrows) never dictates. The first launch asks before it uses fn. When on,
  Navi borrows the fn key setting (`AppleFnUsageType` = 0, "Do Nothing", applied
  with `activateSettings -u`) while it runs and puts it back on quit.
- `Packages/NaviRecording`: record bar, `SCStream` → MP4 (H.264/AAC), mic and
  computer audio (mixed to one track), camera bubble, click and key overlays,
  hide icons, mute notifications, red stop item in the menu bar, GIF, trim.
  The app wires it to the capture overlay (`CaptureFeature.onRecordRequest`)
  and to video cards (`CaptureFeature.videoTools`, `showRecording`).

Not built: swipe to close a card, a Settings window, the Screen Studio-style
video editor.

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

### Capture defaults

- Navi borrows `⇧⌘3` (fullscreen), `⇧⌘4` (area; Space for window), and `⇧⌘5`
  (all-in-one bar) while it runs. `SystemScreenshotShortcuts` turns the macOS
  ones off at launch (IDs 28, 30, 184 in `com.apple.symbolichotkeys`, then
  `activateSettings -u`) and puts them back exactly as they were on quit. A
  backup from an older run keeps its entries; new IDs are added to it. SIGTERM quits the normal way, so
  `pkill` restores them too. No code runs when the app is deleted, so quitting
  is what gives the keys back. The first launch asks; the menu has a toggle.
- Other hotkeys: `⌥⇧⌘4` scrolling capture, `⌥⇧⌘T` capture text, `⌥⇧⌘5` record
  (press again to stop).
- Cards stay on the display where the capture was taken.
- The history keeps a recording as MP4, with `<id>.preview.png` for its
  thumbnail; paste from history pastes the file. Background clears the
  `.navi` markup, so the next markup starts from the background image.
- Recording cards show the duration, an MP4/GIF switch on hover, and Trim in
  the bottom-left corner (`⌘E` on hover). Pin, markup, OCR, and background are
  for images only.
- Save puts files on the Desktop, as `Navi 2026-11-06 at 16.10.12.png`.
  `CaptureSettings.saveFolder` changes it.
- Copy and Save close the card, like CleanShot X. ⌥ + Copy keeps it open. Show
  in Finder keeps it open.
- While the mouse is on a card: `⌘C` copy, `⌘S` save, `⌘W` close. They are
  Carbon hot keys that exist only during the hover, so other apps keep them.
  `⌘E` annotate, `⌘P` pin. CleanShot X works the same way (shortcuts only
  while the mouse is on the card). Card corners: Pin, Close, Annotate, Show in
  Finder.
- Card drag sends the file URL, so the drop keeps the `Navi … .png` name.
- Corner cards do not close on their own (`autoCloseSeconds` = 0). Close with ✕,
  or Close All Cards (menu, or right-click a card). Cards slide in with a small
  bounce. A fullscreen capture shows the shot and closes it, so macOS plays the
  same shrink as the area overlay. No shutter sound.
- No Restore Closed Card. A closed shot stays in `⇧⌘V` history.
- `⌥⇧⌘N` opens the Navi menu at the mouse. The same menu shows from the
  menu bar icon. It is an AppKit `NSStatusItem` menu, built in `NaviMenu`.
- Navi marks its own pasteboard writes with `NaviPasteboard.ownType`, so the
  clipboard watcher does not add a capture twice.

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
| `App/Sources/NaviApp.swift` | Global hot keys, app wiring |
| `App/Sources/NaviMenu.swift` | Menu bar icon and the Navi menu (`⌥⇧⌘N` opens it at the mouse) |
| `Packages/NaviCore` | `Inbox` (shared history store), `CaptureItem`, `HotKey` (Carbon global hotkeys) |
| `Packages/NaviClipboard` | Pasteboard watcher, Maccy-style panel, paste |
| `Packages/NaviRecording` | Screen recording engine, record bar, camera bubble, overlays, GIF, trim |
| `Packages/NaviDictation` | Talk to type: fn key, speech, cleanup, pill, paste |
| `Packages/NaviCapture` | Selection overlay and all-in-one bar, ScreenCaptureKit capture, corner cards, `Annotate/`, `Extras/` (pin, OCR, toast), `Scroll/`, `Background/` |
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
cd Packages/NaviCapture && swift test   # capture, markup, stitch, background tests
cd Packages/NaviRecording && swift test # recording math, GIF, audio mixdown
cd Packages/NaviDictation && swift test # cleanup rules, fn gestures, fn setting
pkill -x Navi; open build/Build/Products/Debug/Navi.app
```

Signing uses the Apple Development certificate, team `77SAW76597`, set in
`project.yml`. `App/Navi.entitlements` (generated from `project.yml`) holds the
microphone and camera entitlements that the hardened runtime needs. Keep a stable signature so macOS keeps the Accessibility and
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
