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
| `--corpus ascii\|pt\|mixed` | ascii | Language of the seeded text. `pt` uses Portuguese words and about 60% of text items contain accented words (ã õ ç é ê á í ó ú à), and 25% end with mixed scripts, emoji, symbols and numbers. `mixed` seeds Cyrillic, Japanese, Arabic, Hindi and emoji items, one script per item |
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
| `add-large-mixed` | `Inbox.add(text:)` of a 2 MB Cyrillic, Japanese and emoji text on a full inbox: the main-actor cost, as in `add`. The save and its search key are built in the background, so they are not in this time |
| `search-common` | `Inbox.search("the")`, which matches most text items |
| `search-rare` | `Inbox.search("quartz")`, which matches about 7% of text items |
| `search-none` | `Inbox.search("zzqxv")`, which matches nothing |
| `search-accent-on-ascii` | `Inbox.search("ação")` on the ASCII corpus |
| `search-cold`, `search-warmup` | The first search on a fresh inbox, and the background key build; see Search below |
| `search-cold-huge` | The first search (`привет`) on a fresh inbox that also holds a 2 MB text with no key yet. That text must be left out and counted as deferred, not folded |
| `search-pt-common`, `-rare`, `-none` | With `--corpus pt`: `search("de")`, `("quartzo")` and `("zzqxv")` |
| `search-pt-accent`, `-accent2` | With `--corpus pt`: `search("ação")` and `("Reunião")` |
| `search-pt-digit`, `-digit2` | With `--corpus pt`: `search("9999")` and `("v2")` |
| `search-pt-mixed`, `-emoji` | With `--corpus pt`: `search("テキスト")` and `("😀")`. A quarter of the items end with Japanese, Cyrillic, emoji with a skin tone, `nº` and `€10` |
| `search-pt-cold-rare`, `-cold-accent`, `-cold-digit`, `-cold-mixed` | With `--corpus pt`: the first search on a fresh inbox, for `quartzo`, `ação`, `9999` and `テキスト` |
| `search-mixed-cyrillic`, `-japanese`, `-arabic`, `-hindi`, `-emoji`, `-none` | With `--corpus mixed`: a word in each script, `😀`, and `zzqxv` |
| `search-mixed-cold-cyrillic`, `-japanese`, `-arabic`, `-hindi`, `-emoji` | With `--corpus mixed`: the first search on a fresh inbox. The `deferred` column is how many items it left out |
| `results` | `ClipboardModel.results` with the query `the` (`de` with `--corpus pt`, `привет` with `--corpus mixed`): the search plus model overhead |
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

## Current numbers

Goal: every main-thread scenario has a p95 under 16.6 ms (one 60 Hz frame) at 200, 1,000 and 5,000 items, on all three corpora. **Met:** every main-thread scenario is under the goal at every size and corpus. The worst main-thread p95 is 10.5 ms (`search-mixed-none`, mixed corpus, 5,000 items).

Background rows (`save-flush`, `search-warmup`) run off the main thread. They show total cost only and are not held to the goal.

Recorded at commit `07feca8` on Apple M4 Pro, macOS 27.2, release build, seed 42, default iterations. Runs: `2026-11-11T02.30.10-07feca8.json` (ascii), `2026-11-11T02.30.37-07feca8.json` (pt) and `2026-11-11T02.32.12-07feca8.json` (mixed). All times in ms.

### ascii corpus (`2026-11-11T02.30.10-07feca8.json`)

| Scenario | 200 med | 200 p95 | 1,000 med | 1,000 p95 | 5,000 med | 5,000 p95 |
|---|---:|---:|---:|---:|---:|---:|
| `load` | 0.653 | 0.688 | 1.199 | 1.790 | 5.637 | 6.062 |
| `add` | 0.072 | 0.094 | 0.244 | 0.308 | 1.343 | 1.551 |
| `save-flush` (background, not main thread) | 1.558 | 1.674 | 6.626 | 6.713 | 32.224 | 34.908 |
| `add-large-mixed` | 0.959 | 1.308 | 1.030 | 2.431 | 2.107 | 2.266 |
| `search-common` | 0.052 | 0.055 | 0.302 | 0.304 | 1.529 | 1.594 |
| `search-rare` | 0.176 | 0.182 | 0.836 | 0.839 | 4.112 | 4.354 |
| `search-none` | 0.183 | 0.184 | 0.878 | 0.880 | 4.408 | 5.269 |
| `search-accent-on-ascii` | 0.297 | 0.300 | 1.439 | 1.442 | 6.852 | 7.317 |
| `search-cold` | 0.123 | 0.125 | 0.659 | 0.687 | 4.272 | 4.706 |
| `search-cold-huge` | 0.258 | 0.278 | 1.260 | 1.339 | 6.014 | 6.021 |
| `search-warmup` (background, not main thread) | 0.115 | 0.124 | 0.621 | 0.682 | 5.072 | 5.362 |
| `results` | 0.052 | 0.055 | 0.279 | 0.296 | 1.468 | 1.506 |
| `thumbnail-open` | 0.121 | 0.131 | 0.133 | 0.145 | 0.124 | 0.137 |
| `thumbnail-draw` | 1.489 | 1.648 | 8.384 | 8.703 | 1.508 | 1.539 |

### pt corpus (`2026-11-11T02.30.37-07feca8.json`)

| Scenario | 200 med | 200 p95 | 1,000 med | 1,000 p95 | 5,000 med | 5,000 p95 |
|---|---:|---:|---:|---:|---:|---:|
| `load` | 0.769 | 0.808 | 1.269 | 1.358 | 5.512 | 7.107 |
| `add` | 0.069 | 0.091 | 0.273 | 0.285 | 1.402 | 1.816 |
| `save-flush` (background, not main thread) | 1.624 | 1.661 | 7.014 | 7.625 | 34.526 | 35.859 |
| `add-large-mixed` | 0.929 | 1.150 | 1.115 | 1.244 | 2.132 | 2.346 |
| `search-pt-common` | 0.041 | 0.042 | 0.198 | 0.427 | 0.955 | 1.021 |
| `search-pt-rare` | 0.205 | 0.228 | 0.956 | 0.958 | 4.776 | 4.900 |
| `search-pt-none` | 0.195 | 0.196 | 0.913 | 0.919 | 4.535 | 4.828 |
| `search-pt-accent` | 0.194 | 0.201 | 0.946 | 0.948 | 4.662 | 4.752 |
| `search-pt-accent2` | 0.039 | 0.039 | 0.209 | 0.211 | 1.113 | 1.181 |
| `search-pt-digit` | 0.187 | 0.190 | 0.873 | 0.876 | 4.371 | 4.740 |
| `search-pt-digit2` | 0.242 | 0.254 | 1.131 | 1.133 | 5.327 | 5.369 |
| `search-pt-mixed` | 0.192 | 0.219 | 0.867 | 0.878 | 4.027 | 4.043 |
| `search-pt-emoji` | 0.190 | 0.207 | 0.874 | 0.911 | 4.086 | 4.315 |
| `search-pt-cold-rare` | 1.643 | 5.830 | 6.029 | 7.310 | 6.102 | 6.112 |
| `search-pt-cold-accent` | 1.399 | 1.796 | 5.352 | 6.051 | 6.116 | 6.137 |
| `search-pt-cold-digit` | 0.490 | 0.587 | 2.445 | 2.516 | 6.108 | 6.124 |
| `search-pt-cold-mixed` | 0.512 | 0.606 | 2.506 | 2.608 | 6.109 | 6.114 |
| `search-cold-huge` | 0.660 | 0.749 | 3.475 | 3.689 | 6.116 | 6.174 |
| `search-warmup` (background, not main thread) | 0.288 | 0.309 | 1.638 | 1.899 | 10.971 | 11.373 |
| `results` | 0.040 | 0.041 | 0.188 | 0.199 | 0.962 | 0.974 |
| `thumbnail-open` | 0.124 | 0.135 | 0.127 | 0.139 | 0.126 | 0.133 |
| `thumbnail-draw` | 1.534 | 1.684 | 1.526 | 1.553 | 8.468 | 9.481 |

### mixed corpus (`2026-11-11T02.32.12-07feca8.json`)

| Scenario | 200 med | 200 p95 | 1,000 med | 1,000 p95 | 5,000 med | 5,000 p95 |
|---|---:|---:|---:|---:|---:|---:|
| `load` | 0.480 | 0.622 | 2.163 | 2.490 | 8.312 | 9.655 |
| `add` | 0.069 | 0.081 | 0.265 | 0.294 | 1.550 | 1.632 |
| `save-flush` (background, not main thread) | 2.476 | 2.672 | 12.495 | 13.282 | 60.077 | 64.889 |
| `add-large-mixed` | 0.923 | 1.865 | 1.025 | 1.123 | 2.400 | 2.777 |
| `search-mixed-cyrillic` | 0.375 | 0.402 | 1.789 | 1.804 | 9.318 | 9.368 |
| `search-mixed-japanese` | 0.339 | 0.570 | 1.711 | 1.859 | 9.102 | 9.465 |
| `search-mixed-arabic` | 0.351 | 0.383 | 1.812 | 1.824 | 9.274 | 9.422 |
| `search-mixed-hindi` | 0.308 | 0.344 | 1.542 | 1.553 | 7.698 | 7.978 |
| `search-mixed-emoji` | 0.328 | 0.347 | 1.568 | 1.586 | 8.237 | 8.598 |
| `search-mixed-none` | 0.403 | 0.406 | 2.044 | 2.061 | 10.462 | 10.544 |
| `search-mixed-cold-cyrillic` | 6.343 | 6.902 | 6.098 | 6.380 | 6.326 | 6.886 |
| `search-mixed-cold-japanese` | 6.389 | 6.856 | 6.133 | 6.771 | 6.295 | 6.586 |
| `search-mixed-cold-arabic` | 6.348 | 6.831 | 6.098 | 6.256 | 6.299 | 6.972 |
| `search-mixed-cold-hindi` | 6.453 | 6.847 | 6.084 | 6.179 | 6.249 | 6.536 |
| `search-mixed-cold-emoji` | 6.406 | 6.922 | 6.100 | 6.554 | 6.291 | 7.110 |
| `search-cold-huge` | 6.461 | 6.769 | 6.136 | 6.285 | 6.229 | 6.561 |
| `search-warmup` (background, not main thread) | 7.964 | 8.255 | 45.529 | 46.101 | 228.709 | 233.587 |
| `results` | 0.337 | 0.347 | 1.793 | 1.820 | 9.378 | 9.465 |
| `thumbnail-open` | 0.129 | 0.149 | 0.125 | 0.135 | 0.122 | 0.130 |
| `thumbnail-draw` | 8.557 | 9.351 | 1.532 | 1.560 | 1.512 | 1.522 |

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

## Search

Search ignores case, accents and character width, the same in every locale, and one rule covers every query: `acao` finds `ação`, `CAFE` finds `café`, `strasse` finds `Straße`, fullwidth `ＡＢＣ` finds `abc`. It matches the text and the source app name, in display order. This replaces the earlier `localizedCaseInsensitiveContains` filter, which kept accents and treated some queries differently (digits, accents in mixed normalization forms), and which scanned every item on every call.

How it works (`SearchCache`, `SearchFold`):

- Each item has a key for its text and for its source app: the bytes of `string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)`. A search folds the query the same way and looks for the bytes with `memmem`.
- The key is built without calling the system fold for every text. ASCII is lowercased eight bytes at a time. Characters from U+0080 to U+02FF come from a table. Others come from a cache filled by the system fold, one character (with the marks after it) at a time. A text with a character whose fold depends on its neighbors (CJK compatibility ideographs, emoji skin tones, some spaces and marks above U+036F) has the system fold applied only to the stretch around it, between two ASCII-adjacent spaces. Every item gets a key; nothing falls back to a scan.
- The fold equals the system fold byte for byte. `InboxSearchTests` checks it on 20,000 random texts and every BMP scalar. A one-off check of about 21 million random texts and 10 million scalar cases found no difference.
- Keys for a new item up to 16 KB are built when it is added (under 1 ms even for non-Latin text). A bigger text is handed to the background builder. A search never builds such a key itself: until it lands, the search leaves that item out and counts it in `Inbox.deferredSearchItems`. After `Inbox.init`, a background task builds the keys of the loaded items, 500 at a time, and installs each batch on the main actor.
- Until the keys exist, a search builds missing ones up to 16 KB itself, but only for `Inbox.searchBudget` (6 ms, on a monotonic clock). Items still without a key when that runs out are left out of that search and counted in `Inbox.deferredSearchItems`; they are never dropped for good. Each installed batch changes `Inbox.searchKeysVersion`, which `search` reads, so `ClipboardModel.results` and the list that shows it recompute by themselves and the results fill in. In practice that is a few milliseconds for Latin text and about 0.2 s for 5,000 Arabic, Hindi or Japanese items, only for the first search after launch.
- The system-fold caches are bounded: the scalar cache clears at 16,384 entries, the cluster cache at 2,048, and clusters over 64 bytes are not cached, so stacks of combining marks cannot grow them.

What the new search no longer matches that the old one did, from a one-off check of 1.5 million random query and text pairs in en_US, pt_BR and de_DE (0.06% of pairs with realistic characters, 0.5% with the exotic ones): compatibility forms of digits (`1` finding `¹` or `①`, `２` finding `²`), `ß` finding a single `s`, composed Hangul or kana (`가` finding `ᄀ`+`ᅡ`, `ガ` finding `カ` + voicing mark) when the other form has the pieces, and queries that are only combining marks, zero-width characters or Devanagari/Arabic marks. Plain Portuguese, English and accented text lost nothing. It matches more: for example `Reuniao` finds `Reunião`, and accents are ignored when the query has a digit.

| Scenario | What it times |
|---|---|
| `search-cold` | A fresh `Inbox` from disk, then the first search at once. Only main-actor work is timed; the background build runs beside it |
| `search-warmup` | From the end of `Inbox.init` until the background build has installed every key |

Median and p95 in ms at 5,000 items, from the search change's own runs at `6ebe147`; current numbers are under Current numbers. Before is the original filter (ASCII baseline above, run 2). After is `2026-11-11T02.02.03-6ebe147.json` (default corpus, second run), `2026-11-11T02.02.14-6ebe147.json` (`--corpus pt`) and `2026-11-11T02.02.48-6ebe147.json` (`--corpus mixed`). The previous version of this change had `search-pt-rare` at about 47 ms, `search-pt-none` at 49, `search-pt-accent` at 25 and `search-pt-accent2` at 36 on a similar Portuguese history; those were review measurements, not saved.

| Scenario | Before median | Before p95 | After median | After p95 | Deferred |
|---|---:|---:|---:|---:|---:|
| search-common | 8.683 | 9.067 | 1.426 | 1.443 | |
| search-rare | 33.277 | 33.600 | 3.729 | 3.751 | |
| search-none | 34.271 | 34.624 | 3.885 | 3.947 | |
| search-accent-on-ascii | | | 6.404 | 6.437 | |
| results | 8.427 | 8.809 | 1.457 | 1.556 | |
| search-cold | n/a | n/a | 3.983 | 4.354 | 0 |
| search-warmup (background) | n/a | n/a | 4.683 | 4.894 | |
| search-pt-common | | | 0.940 | 0.954 | |
| search-pt-rare | | | 4.317 | 4.360 | |
| search-pt-none | | | 4.147 | 4.187 | |
| search-pt-accent | | | 4.252 | 4.366 | |
| search-pt-digit2 | | | 5.211 | 5.237 | |
| search-pt-mixed | | | 3.932 | 4.107 | |
| search-pt-cold-rare | | | 6.094 | 6.098 | 2597 |
| search-pt-cold-accent | | | 6.113 | 6.132 | 2607 |
| search-pt-cold-digit | | | 6.104 | 6.172 | 2618 |
| search-pt-cold-mixed | | | 6.107 | 6.144 | 2677 |
| search-warmup, pt (background) | | | 10.130 | 10.785 | |
| search-mixed-cyrillic | | | 6.178 | 6.241 | |
| search-mixed-none | | | 7.646 | 7.681 | |
| results, mixed corpus | | | 9.676 | 9.994 | |
| search-mixed-cold-cyrillic | | | 6.250 | 6.316 | 4906 |
| search-mixed-cold-japanese | | | 6.247 | 6.475 | 4914 |
| search-mixed-cold-arabic | | | 6.255 | 6.450 | 4916 |
| search-mixed-cold-hindi | | | 6.251 | 6.612 | 4916 |
| search-mixed-cold-emoji | | | 6.232 | 6.481 | 4924 |
| search-warmup, mixed (background) | | | 223.717 | 225.496 | |

Every search scenario, cold included, is under 16.6 ms at p95 at 200, 1,000 and 5,000 items on all three corpora; the worst is 10.5 ms (`search-mixed-none`, mixed corpus, 5,000 items, a warm `memmem` over 22 MB of keys) on `07feca8`, see Current numbers. The cold searches stay near the 6 ms budget whatever the script. The warm-up rows run on a background thread, not the main actor. `load`, `add` and the thumbnail scenarios do not touch this code and are within noise of the baseline.

### Bench isolation for `load` and the cold searches

Each timed `load` and each cold search used to start while the previous run's `Inbox` was still building search keys in the background and was freed inside the timer. On the mixed corpus that made `load` read 23.5 ms median (41 ms p95) at 5,000 items, and `search-mixed-cold-arabic` spike to 18 ms p95 at 200 items. The decode itself is about 9 ms there (read 1.4 ms, decode 8 to 11 ms, sort 0.4 ms), already split into byte-balanced pieces over the core count. The bench now waits for the previous inbox's build to finish and frees it before each run, outside the timer. Mixed `load` is 8.3 ms median and 9.7 ms worst p95 over all sizes on `07feca8`; every cold search is 7 ms or less at p95 at every size and corpus.
