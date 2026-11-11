# Performance

## History benchmark

`history-bench` times the History list (`⇧⌘V`) on synthetic histories of 200, 1,000 and 5,000 items. It never reads or writes your real history.

Run it from the package folder, in release. It needs the Xcode toolchain: `xcode-select -p` must point at `Xcode.app`, not Command Line Tools, or the SwiftUI macros do not build.

```sh
cd Packages/NaviClipboard && swift run -c release history-bench --save
```

| Option | Default | Meaning |
|---|---|---|
| `--sizes 200,1000,5000` | 200,1000,5000 | History sizes to seed and time |
| `--iterations N` | 20 | Timed runs per scenario at 1,000 items and up, after three discarded warm-up runs. Smaller sizes get more, see below |
| `--seed N` | 42 | Seed for the synthetic history. The same seed gives the same content |
| `--json` | off | Print the report as JSON instead of a table |
| `--save` | off | Write `Bench/results/<date>-<commit>.json` (date to the second, commit = short HEAD when run) |

### Iteration rule

Small histories finish in microseconds, where timer noise and warm-up drift dominate, so they get more timed runs. Each size gets `--iterations × max(1, 1000 / size)` timed runs. At the default of 20, that is 100 runs at 200 items, 20 at 1,000 items and 20 at 5,000 items. Every scenario runs three untimed warm-up runs first.

### How the history is built

Each size gets a fresh temporary directory, deleted at the end. The bench writes `history.json` and `files/` in the format `Inbox` reads.

- 80% text items, 20 to 4,000 characters, words from a fixed vocabulary.
- 20% PNG images: two 2560×1600 and two 800×600 pictures, rendered once and reused.
- The inbox limit is size + 100, so no seeded item is evicted.

### Scenarios

| Scenario | What it times |
|---|---|
| `load` | `Inbox(directory:limit:)`: reads and decodes `history.json`, then sorts |
| `add` | `Inbox.add(text:)` on a full inbox: what the main actor pays. The background save is handed off, not waited for. The added item is removed and flushed outside the timer |
| `save-flush` | `Inbox.add(text:)` plus `Inbox.flush()`: the total persistence cost, including the background encode and write |
| `search-common` | `Inbox.search("the")`, which matches most text items |
| `search-rare` | `Inbox.search("quartz")`, which matches about 7% of text items |
| `search-none` | `Inbox.search("zzqxv")`, which matches nothing |
| `results` | `ClipboardModel.results` with the query `the`: the search plus model overhead |
| `thumbnail-open` | `ClipboardModel.image(for:)` on an image item. A new model per run, so the cache is always empty. `NSImage` reads the file lazily, so this covers reading the file and creating the image. The pixel decode is not included |
| `thumbnail-draw` | `ClipboardModel.image(for:)` on an uncached image item, then a draw into a 2× bitmap of the row frame (200×40 points, aspect fit, as `ClipboardListView` shows it). The draw forces the pixel decode that a row pays on first paint |

The image item is the first image in the history, so it can differ between sizes.

Each scenario reports the median, p95 and minimum in milliseconds. `matches` is the number of items the last run returned.

## Signposts

The History code emits `os_signpost` intervals under subsystem `com.donovanhiland.navi`, category `History`.

| Interval | Where | Covers |
|---|---|---|
| `PanelShow` | `ClipboardPanelController.show()` | From the call until the panel is ordered front |
| `Search` | `ClipboardModel.results` | Filtering the inbox for the current query |
| `RowImage` | `ClipboardModel.image(for:)` | A cache miss: reading and creating the row image |
| `InboxSave` | `Inbox` (NaviCore) | Encoding and writing `history.json` |

Limitation: `RowImage` ends when `image(for:)` returns, before the row draws. The pixel decode happens at draw time, so it is not inside the interval. The `thumbnail-draw` scenario measures that cost; a draw-time signpost is a follow-up.

### Recording a trace

Start the debug app first, then run this. It attaches to the process named `Navi` for 60 seconds. Open the History panel several times while it records.

```sh
xcrun xctrace record --template 'Time Profiler' --instrument 'os_signpost' --instrument 'Points of Interest' --attach Navi --time-limit 60s --output "$HOME/Desktop/navi-history.trace"
```

Open the `.trace` file in Instruments. In the `os_signpost` track, filter by subsystem `com.donovanhiland.navi`. The intervals above appear under category `History`.

## Baseline

Recorded on:

- Machine: Apple M4 Pro, macOS 27.2 (26B123)
- Toolchain: Xcode's Swift and SDK (macOS 27.2), release build
- Settings: seed 42, 20 timed runs per scenario at 1,000 and 5,000 items, 100 at 200 items, 3 warm-up runs
- Commit: `3356977`, the commit the code was built on before this change

The two runs were made one after the other, at 21:20:24 and 21:20:36 on 2026-11-10. Both are in `Packages/NaviClipboard/Bench/results/`: `2026-11-10T21.20.24-3356977.json` and `2026-11-10T21.20.36-3356977.json`.

### 200 items (history.json 380 KB)

| Scenario | Median, run 1 (ms) | Median, run 2 (ms) | Spread | p95, run 2 (ms) | Matches |
|---|---:|---:|---:|---:|---:|
| load | 0.702 | 0.687 | -2.2% | 0.794 | - |
| add | 1.821 | 1.814 | -0.4% | 2.424 | - |
| search-common | 0.320 | 0.323 | +0.9% | 0.362 | 155 |
| search-rare | 1.402 | 1.401 | -0.0% | 1.636 | 14 |
| search-none | 1.450 | 1.444 | -0.4% | 1.539 | 0 |
| results | 0.322 | 0.323 | +0.5% | 0.373 | 155 |
| thumbnail-open | 0.135 | 0.131 | -3.0% | 0.163 | - |
| thumbnail-draw | 1.691 | 1.682 | -0.5% | 1.923 | - |

### 1000 items (history.json 1825 KB)

| Scenario | Median, run 1 (ms) | Median, run 2 (ms) | Spread | p95, run 2 (ms) | Matches |
|---|---:|---:|---:|---:|---:|
| load | 3.483 | 3.494 | +0.3% | 3.812 | - |
| add | 7.679 | 7.868 | +2.5% | 10.244 | - |
| search-common | 1.749 | 1.675 | -4.2% | 3.037 | 746 |
| search-rare | 6.743 | 6.692 | -0.8% | 8.020 | 64 |
| search-none | 7.020 | 6.997 | -0.3% | 7.195 | 0 |
| results | 1.729 | 1.668 | -3.5% | 1.839 | 746 |
| thumbnail-open | 0.143 | 0.134 | -5.9% | 0.285 | - |
| thumbnail-draw | 11.018 | 8.956 | -18.7% | 9.089 | - |

### 5000 items (history.json 8918 KB)

| Scenario | Median, run 1 (ms) | Median, run 2 (ms) | Spread | p95, run 2 (ms) | Matches |
|---|---:|---:|---:|---:|---:|
| load | 17.333 | 17.315 | -0.1% | 18.434 | - |
| add | 36.203 | 35.937 | -0.7% | 37.624 | - |
| search-common | 8.662 | 8.683 | +0.3% | 9.067 | 3704 |
| search-rare | 33.261 | 33.277 | +0.0% | 33.600 | 280 |
| search-none | 34.439 | 34.271 | -0.5% | 34.624 | 0 |
| results | 8.635 | 8.427 | -2.4% | 8.809 | 3704 |
| thumbnail-open | 0.133 | 0.144 | +8.5% | 0.254 | - |
| thumbnail-draw | 1.699 | 1.711 | +0.7% | 2.076 | - |

### Run-to-run variance

Spread is run 2 against run 1, on the median. The target is within 15% for every scenario at every size.

- 200 items: every scenario is within 3%. Met, with the iteration rule above.
- 5,000 items: every scenario is within 9%. Met.
- 1,000 items: every scenario but one is within 6%. `thumbnail-draw` moved 18.7% (11.0 ms to 9.0 ms), which misses the target. Two more runs at 1,000 items, not saved, gave 9.76 ms and 9.76 ms, so run 1 looks like an outlier: its p95 was 28.9 ms against 9.1 ms in run 2. The cause is not established. Compare `thumbnail-draw` changes with a fresh pair of runs before trusting a difference under 20%.

No scenario has a median under 0.1 ms, so none is below timer resolution.

## Saving

`Inbox` used to encode all items and rewrite `history.json` on the main actor for every change. It now hands a snapshot to `HistoryWriter`, which encodes and writes on one serial background queue. A pending snapshot is replaced by a newer one, so bursts coalesce and the latest state wins. `Inbox.flush()` blocks until the last snapshot is written; the app calls it in `applicationWillTerminate`. `add` also inserts at its sorted position instead of sorting everything.

Before is commit `3356977` (the baseline above), after is the change on `aba62bf`. The `add` scenario now measures the main-actor cost only; `save-flush` is the full cost and is about the old `add`.

| 5,000 items | Before median (ms) | Before p95 (ms) | After median (ms) | After p95 (ms) |
|---|---:|---:|---:|---:|
| add | 35.937 | 37.624 | 0.502 | 0.594 |
| save-flush | - | - | 33.921 | 35.227 |

At 1,000 items `add` goes from 7.9 ms (p95 10.2) to 0.14 ms (p95 0.31), and at 200 items from 1.8 ms to 0.05 ms. The other scenarios are unchanged within noise (the second saved run was noisy on `search-*`). Saved runs: `2026-11-10T23.33.20-aba62bf.json` and `2026-11-10T23.33.30-aba62bf.json`.

## Loading

`Inbox(directory:)` read and decoded `history.json` on the calling thread, 16.4 ms at 5,000 items. The file is now cut at item boundaries and the pieces decode in parallel. The format on disk is unchanged, so existing files load as before.

- Tried and dropped: `Data(contentsOf:options: .mappedIfSafe)` (no gain, 17.1 ms) and `JSONSerialization` with hand-built items (38 ms, slower than `JSONDecoder`).
- Kept: files of 512 KB and up are split at `},{"`, which only ever sits between two items because quotes inside strings are escaped. Each piece decodes on its own core. A file that is not in `JSONEncoder`'s compact form, or a piece that fails, falls back to one plain decode.
- Runs: `2026-11-10T23.34.31-aba62bf.json` and `2026-11-10T23.34.38-aba62bf.json`. Other scenarios did not change.

| Size | Load median before (ms) | p95 before (ms) | Load median after (ms) | p95 after (ms) |
|---|---:|---:|---:|---:|
| 200 | 0.647 | 0.660 | 0.665 | 0.690 |
| 1,000 | 3.172 | 3.216 | 1.127 | 1.177 |
| 5,000 | 16.365 | 16.676 | 5.345 | 5.519 |

Before is an unsaved run on the same machine just before the change. The second saved run measured 6.0 ms median and 6.2 ms p95 at 5,000.
