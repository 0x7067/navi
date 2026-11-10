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
  and screen color sampler, three line sizes, select/move/delete marks (after you draw,
  the tool goes back to the pointer with the new mark selected; a dashed outline
  shows it; drag a corner, an end, or anywhere on an edge to resize; the cursor
  shows what a drag does; the color and size pickers change the selected mark;
  the counter tool stays on for the next step; spotlight is a rounded box), `⌘Z`/`⇧⌘Z`/Delete through a local key monitor,
  rotate, flip, resize, crop, undo/redo, drop an image in to combine, a small
  picture of the shot to drag into any app (top right, beside Cancel and Done), Done updates the card and the history item. Marks stay editable in
  `<id>.navi` (JSON + base PNG) beside the Inbox file.
- Step 3 (`Extras/`): pin to screen (move, scroll to resize, opacity, lock so
  clicks go through, unlock from the menu), Capture Text (OCR + QR, Vision),
  self-timer, all-in-one bar on `⇧⌘5`, card quick actions (right-click).
- Step 4: scrolling capture (`Scroll/`, Vision registration, vertical and
  horizontal, Auto-scroll), background tool (`Background/`: gradients, solid,
  picture, padding, corners, shadow, aspect ratio, auto balance, presets).

**Talk to type and step 5 are built, not checked by Donovan yet:**
- `Packages/NaviDictation`: hold fn to talk, double-tap fn to lock, pill with
  a waveform, on-device speech (Parakeet TDT v3 through FluidAudio, from Hex;
  `SpeechAnalyzer` or `SFSpeechRecognizer` until the Parakeet model is loaded.
  The model, about 0.5 GB, downloads on first start to
  `~/Library/Application Support/FluidAudio/Models`), cleanup with Foundation Models or rules, paste at the
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
- **Talk to type follows Hex** (`anomalyco/hex`, MIT, from the OpenCode
  team). Port Hex's features; do not design new dictation features from
  scratch. `docs/upstream-hex.md` has the feature map, what to port next, and
  the sync steps. Check each port with the dictation benchmark
  (`cd Packages/NaviDictation && swift run dictation-bench`).
- **Single window capture** uses `SCContentFilter(desktopIndependentWindow:)`,
  so nothing behind the window gets in.

### Capture defaults

- Navi borrows `⇧⌘3` (fullscreen), `⇧⌘4` (area; Space for window), `⇧⌘5`
  (all-in-one bar), and `⌃⇧⌘3` / `⌃⇧⌘4` (the same shots, also copied to the
  clipboard) while it runs. `SystemScreenshotShortcuts` turns the macOS
  ones off at launch (IDs 28, 29, 30, 31, 184 in `com.apple.symbolichotkeys`, then
  `activateSettings -u`) and puts them back exactly as they were on quit. A
  backup from an older run keeps its entries; new IDs are added to it. SIGTERM quits the normal way, so
  `pkill` restores them too. No code runs when the app is deleted, so quitting
  is what gives the keys back. The first launch asks; the menu has a toggle.
- In the `⇧⌘5` all-in-one bar, a dragged area stays on screen, like macOS:
  drag inside to move it, drag a corner to resize it, pick Area, Scrolling,
  Text, or Record in the bar, then press the bar's Capture/Record button or
  Return. `⇧⌘4` still captures as soon as the drag ends.
- Other hotkeys: `⌥⇧⌘4` scrolling capture, `⌥⇧⌘T` capture text, `⌥⇧⌘5` record
  (press again to stop).
- Shots leave out Navi's overlays, cards, pins, and pills (window layer above 0)
  but keep Navi's normal windows, such as the markup editor.
- The selection overlay shows at once over the live screen. The frozen screen
  images arrive about 0.2 s later and are what gets cropped; a selection that
  ends first waits for them.
- Cards stay on the display where the capture was taken.
- The history keeps a recording as MP4, with `<id>.preview.png` for its
  thumbnail; paste from history pastes the file. Background clears the
  `.navi` markup, so the next markup starts from the background image.
- Recording cards show the duration, an MP4/GIF switch on hover, and Trim in
  the bottom-left corner (`⌘E` on hover). Pin, markup, OCR, and background are
  for images only.
- Save puts files on the Desktop, as `Navi 2026-11-06 at 16.10.12.png`.
  `CaptureSettings.saveFolder` changes it.
- Every screenshot goes to the clipboard as soon as it is taken, and again after
  markup Done (`CaptureSettings.copyToClipboard`, on by default; menu toggle
  "Copy Screenshots to Clipboard").
- Each capture is its own history item, even when its pixels match an older
  shot (`Inbox.add(fileData:…, deduplicate: false)`). Saved markup opens only
  while the history file is still that markup's flat image.
- Markup editor keys: V select, A arrow, R rectangle, F filled rectangle,
  O ellipse, L line, P pencil, H highlighter, T text, N counter, B blur,
  X pixelate, S spotlight, C crop. Text: the box takes focus at once; a click
  outside keeps the text and selects it; drag text with the text or select
  tool; click selected text to edit it; Esc ends typing.
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
(GPL-3.0) and `lzhgus/Capso` (BSL 1.1). Code you **may copy**, with its MIT
notice kept: `anomalyco/hex`. Ideas to borrow: Shottr's pixel ruler,
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
| `docs/upstream-hex.md` | Hex as the upstream for talk to type: feature map, sync steps |
| `Packages/NaviDictation/Bench` | Dictation benchmark cases and saved results |

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
NAVI_SNAPSHOTS=/tmp/navi-snaps swift test --filter EditorSnapshot  # in NaviCapture: draws the markup editor to PNGs (760/1000/1400 wide, dark and light) to check its look
cd Packages/NaviRecording && swift test # recording math, GIF, audio mixdown
cd Packages/NaviDictation && swift test # cleanup rules, fn gestures, fn setting, scoring
cd Packages/NaviDictation && swift run dictation-bench [--audio [--speech apple,parakeet]] [--failures] [--save]
pkill -x Navi; open build/Build/Products/Debug/Navi.app
```

Releases live on GitHub (`donovanhiland/navi` is public). Run
`scripts/release.sh <version> "<notes>"`: it bumps the version and build number
in `project.yml`, runs `scripts/share.sh`, signs the update with the Sparkle key
(EdDSA, private half in the login keychain; public half is `SUPublicEDKey` in
`project.yml`), writes `appcast.xml`, and makes the release. Share
`https://github.com/donovanhiland/navi/releases/latest/download/Navi.zip`.
Navi checks `…/releases/latest/download/appcast.xml` daily and from "Check for
Updates…" in the menu. Debug builds never update themselves.

The app icon is drawn by `scripts/make-icon.swift` into
`App/Assets.xcassets/AppIcon.appiconset`.

To build a shareable copy without releasing it, run `scripts/share.sh`. It archives Release,
then Xcode signs it with Developer ID, notarizes it with the Apple account
signed in to Xcode, and staples it. Output: `dist/Navi.zip`. Not
TestFlight or the App Store: both need the app sandbox, which blocks the system
shortcut and paste features.

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
