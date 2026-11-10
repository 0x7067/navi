<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Navi icon">
</p>

<h1 align="center">Navi</h1>

<p align="center">
  <b>Copy, screenshot, mark up, record, and talk to type. One menu bar app. Nothing leaves your Mac.</b>
</p>

<p align="center">
  <a href="https://github.com/donovanhiland/navi/releases/latest/download/Navi.zip"><img src="https://img.shields.io/badge/download-latest-8a4fff?style=flat-square" alt="Download"></a>
  <a href="https://github.com/donovanhiland/navi/releases/latest"><img src="https://img.shields.io/github/v/release/donovanhiland/navi?style=flat-square&label=version" alt="Version"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-555?style=flat-square" alt="macOS 15+">
  <img src="https://img.shields.io/badge/cloud-none-2ea44f?style=flat-square" alt="No cloud">
</p>

---

## Why Navi

Your menu bar is full of capture apps: one for clipboard history, one for
screenshots, one for recordings, one for dictation. Each one asks for its own
permissions, has its own shortcuts and settings, and keeps your stuff in its own
corner. Some send your screen or your voice to a server.

Navi is all four in one app:

- **One place for everything you capture.** Copied text, screenshots,
  recordings, GIFs, text from images, and dictated text all land in one history.
  Press `⇧⌘V`, type a few letters, and paste.
- **One set of permissions.** Grant Screen Recording, Accessibility, and
  Microphone once.
- **The shortcuts you already know.** `⇧⌘3`, `⇧⌘4`, and `⇧⌘5` take Navi
  screenshots while Navi runs. Quit Navi and macOS gets them back.
- **Private by design.** Speech-to-text, cleanup, OCR, and editing all run on
  your Mac. There's no account, no upload, and no "share to cloud" button. The
  only thing Navi fetches is the update check.
- **Native and fast.** Swift, SwiftUI, and AppKit. No Electron.

## Features

### 📋 Clipboard history

Keyboard first, like Maccy.

- `⇧⌘V` opens your history at the mouse. Type to filter, then press Return to paste.
- `⌘1`–`⌘9` paste the top items. `⌥P` pins an item, `⌥⌫` deletes it.
- Images, files, screenshots, recordings, and dictated text live in the same list.
- Skips anything a password manager marks as private.

### 📸 Screenshots

Inspired by CleanShot X.

- `⇧⌘4`: drag an area. Edges snap to windows. A magnifier shows the exact pixel
  and the size. Press Space to pick a whole window instead.
- `⇧⌘3`: the full screen. `⇧⌘5`: a bar with every capture mode.
- `⌃⇧⌘3` / `⌃⇧⌘4`: the same shots, also copied to the clipboard.
- The screen freezes the moment you press the keys, so menus, tooltips, and
  video frames stay put while you drag.
- Every shot drops into a **corner card**. Copy it, save it, drag it into any
  app, pin it, or mark it up. While the mouse is on a card: `⌘C` copy, `⌘S`
  save, `⌘W` close, `⌘E` mark up, `⌘P` pin.
- **Scrolling capture** (`⌥⇧⌘4`) stitches a long page into one image.
- **Capture text** (`⌥⇧⌘T`) copies the words in any area of the screen, and
  reads QR codes too.
- **Pin to screen** keeps a shot floating above every window. Scroll to resize
  it, change its opacity, or lock it so clicks pass through.
- **Backgrounds** wrap a shot in a gradient, a solid color, or a picture, with
  padding, rounded corners, and a shadow. Ready for a tweet or a slide.
- **Self-timer** and **Hide desktop icons**.

### ✏️ Markup

<p align="center"><img src="docs/images/markup.png" alt="The Navi markup editor" width="900"></p>

- Arrow, box, filled box, oval, line, pencil, highlighter, text, and numbered steps.
- Blur or pixelate to hide things. Spotlight to make one part stand out.
- Every mark stays editable: drag it, grab an edge or a corner to resize it,
  and change its color or line size after you draw it.
- Crop, rotate, flip, and resize. Drop in a second image to combine them.
- `⌘Z` / `⇧⌘Z` to undo and redo.
- Drag the little preview into Slack, Mail, or Messages. No need to save first.

### 🎙️ Talk to type

Inspired by Wispr Flow. The speech engine comes from [Hex](https://github.com/anomalyco/hex).

- **Hold fn and talk.** Let go, and your words appear wherever you're typing.
- **Double-tap fn** to keep listening, hands-free.
- **Cleans up as you talk.** It drops "um" and "uh," fixes stumbles, adds
  punctuation, and tidies rambles, using Apple's on-device AI.
- **Fast, private speech-to-text** with Parakeet TDT v3 on the Neural Engine.
  On our benchmark it makes about a third fewer mistakes than Apple's built-in
  speech engine.
- fn with another key (fn + arrows, fn + Delete) still works as usual.

### 🎬 Screen recording

- `⌥⇧⌘5` to start, and again to stop. Record the full screen, a window, or an area.
- Mic and computer sound, a camera bubble, and on-screen clicks and keys.
- Hides desktop icons and mutes notifications in the recording only. Your real
  screen doesn't change.
- Save as MP4 or GIF. Trim the ends.

## Install

1. [**Download Navi.zip**](https://github.com/donovanhiland/navi/releases/latest/download/Navi.zip).
2. Unzip it and drag **Navi** into **Applications**.
3. Open it. Navi is signed and notarized by Apple, so it opens without a warning.

Navi updates itself. It checks once a day, or use **Check for Updates…** in the Navi menu.

### First launch

- **Permissions.** Navi asks for Screen Recording (screenshots and recordings),
  Accessibility (paste and global shortcuts), and Microphone (talk to type and
  recordings).
- **Screenshot keys.** Navi asks before it takes over `⇧⌘3`, `⇧⌘4`, `⇧⌘5`,
  `⌃⇧⌘3`, and `⌃⇧⌘4`. It turns the macOS versions off while it runs, and turns
  them back on exactly as they were when you quit. You can switch this off in
  the Navi menu.
- **fn key.** Navi asks before it uses fn for talk to type. While it does, it
  sets macOS's "Press 🌐 key to" setting to "Do Nothing," and puts it back when
  you quit.
- **Speech model.** The first time you use talk to type, Navi downloads the
  speech model (about 0.5 GB). Until it's ready, Apple's speech engine fills in.

## Shortcuts

| Keys | What it does |
|---|---|
| `⇧⌘V` | Clipboard history |
| `⇧⌘4` | Screenshot an area (Space: pick a window) |
| `⇧⌘3` | Screenshot the full screen |
| `⇧⌘5` | All-in-one capture bar |
| `⌃⇧⌘4` / `⌃⇧⌘3` | Area / full screen, also copied to the clipboard |
| `⌥⇧⌘4` | Scrolling capture |
| `⌥⇧⌘T` | Capture text (OCR and QR codes) |
| `⌥⇧⌘5` | Start or stop recording |
| `⌥⇧⌘N` | Open the Navi menu at the mouse |
| Hold `fn` | Talk to type |
| Double-tap `fn` | Talk to type, hands-free |

## Privacy

- Everything you capture stays in `~/Library/Application Support/Navi/` on your Mac.
- Speech-to-text, cleanup, OCR, and image editing run on your Mac.
- No accounts, analytics, or uploads.
- Network use: the daily update check against this repo's Releases, and the
  one-time speech model download.

## Requirements

- macOS 15 or later.
- macOS 26 or later with Apple Intelligence turned on for the AI cleanup in
  talk to type. Without it, Navi uses simple rules to remove filler words.

## Status

Navi is an early test build. Clipboard history and the core screenshot flow are
well tested. Markup, scrolling capture, talk to type, and recording are
new. Please [open an issue](https://github.com/donovanhiland/navi/issues) when
something breaks.

Not built yet: a Home window that shows all your captures, a Settings window,
and a full video editor.

## Build from source

You need Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
git clone https://github.com/donovanhiland/navi.git
cd navi
xcodegen generate
xcodebuild -project Navi.xcodeproj -scheme Navi -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Navi.app
```

Signing is set up for one developer team in `project.yml`. To build on your
own machine, change `DEVELOPMENT_TEAM` to your team, or sign to run locally in
Xcode.

Tests are per feature package:

```sh
cd Packages/NaviCore && swift test
cd Packages/NaviCapture && swift test
cd Packages/NaviRecording && swift test
cd Packages/NaviDictation && swift test
```

### Dictation benchmark

`Packages/NaviDictation` has a benchmark with 51 cases (fillers, stumbles,
corrections, lists, spoken punctuation, tech terms, and rambles). It scores
pass rate, word accuracy, made-up words, fillers left, and speed:

```sh
cd Packages/NaviDictation
swift run dictation-bench                                   # cleanup only, on typed input
swift run dictation-bench --audio --speech apple,parakeet   # speak, transcribe, then clean up
```

### Releasing

```sh
scripts/release.sh 0.2.0 "What changed."
```

It bumps the version, builds a Release copy, signs it with Developer ID, gets
Apple's notarization, signs the update for Sparkle, and publishes a GitHub
release. Installed copies pick it up within a day.

## How it's built

One Swift package per feature, all talking through a shared core:

| Package | Holds |
|---|---|
| `NaviCore` | The shared history (`Inbox`), capture items, global hot keys |
| `NaviClipboard` | Clipboard watcher, history panel, paste |
| `NaviCapture` | Screenshots, corner cards, markup, pins, OCR, scrolling capture, backgrounds |
| `NaviRecording` | Screen recording, camera bubble, click and key overlays, GIF, trim |
| `NaviDictation` | fn key, speech-to-text, cleanup, paste at the cursor, benchmark |

The app (`App/`) wires them together and owns the menu bar icon.

## Thanks

- [Hex](https://github.com/anomalyco/hex) (MIT): talk to type follows Hex, and
  its Parakeet speech code is adapted from it.
- [FluidAudio](https://github.com/FluidInference/FluidAudio): Parakeet on Apple's Neural Engine.
- [Sparkle](https://sparkle-project.org): updates.
- [Maccy](https://github.com/p0deje/Maccy), [CleanShot X](https://cleanshot.com),
  and [Wispr Flow](https://wisprflow.ai): the apps whose ideas shaped Navi.
