import AppKit
import Foundation
import NaviClipboard
import NaviCore

/// Seeds each size, times every scenario, and returns the report.
@MainActor
func runBench(_ options: BenchOptions, packageRoot: URL) throws -> BenchReport {
    let sizes = try options.sizes.map { try benchmarkSize($0, options: options) }
    return BenchReport(
        recorded: ISO8601DateFormatter().string(from: .now),
        commit: gitShortCommit(in: packageRoot),
        machine: Machine(
            cpu: sysctlString("machdep.cpu.brand_string") ?? "unknown",
            macOS: ProcessInfo.processInfo.operatingSystemVersionString
        ),
        seed: options.seed,
        corpus: options.corpus.rawValue,
        iterations: options.iterations,
        sizes: sizes
    )
}

/// Times each scenario on a history of `count` items in a fresh temporary directory, removed at the end.
@MainActor
private func benchmarkSize(_ count: Int, options: BenchOptions) throws -> SizeResult {
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "history-bench-\(count)-\(UUID().uuidString)", directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    try HistorySeeder.write(count: count, seed: options.seed, corpus: options.corpus, to: directory)
    let bytes = try fileSize(directory.appending(path: "history.json"))
    // Above `count`, so `add` never evicts a seeded item.
    let limit = count + 100
    let inbox = Inbox(directory: directory, limit: limit)
    guard inbox.items.count == count else {
        throw BenchError.seeding(expected: count, found: inbox.items.count)
    }
    // Small histories take microseconds, where timer noise dominates, so they get more timed runs:
    // iterations × max(1, 1000 / size). At the default 20 that is 100 runs at 200 items, 20 at 1,000 and up.
    let runs = options.iterations * max(1, 1000 / count)
    var scenarios: [ScenarioResult] = []

    // Each load starts on an idle machine: the previous inbox's background key build finishes and the inbox is
    // freed outside the timer, so its work does not slow the load being timed.
    var previous: Inbox?
    let load = sample(runs, prepare: { settle(&previous) }, run: { _ in
        let loaded = Inbox(directory: directory, limit: limit)
        previous = loaded
        return loaded.items.count
    })
    settle(&previous)
    scenarios.append(ScenarioResult(name: "load", milliseconds: load.milliseconds))

    let filler = String(repeating: "the report ", count: 150)
    var added: UUID?
    var counter = 0
    let add = sample(runs, prepare: {
        if let id = added {
            inbox.remove(id)
            inbox.flush() // Outside the timer: each timed add starts with an idle writer.
            added = nil
        }
    }, run: { _ in
        counter += 1
        added = inbox.add(text: "bench add \(counter) " + filler)?.id
        return 1
    })
    if let id = added { inbox.remove(id) }
    inbox.flush()
    scenarios.append(ScenarioResult(name: "add", milliseconds: add.milliseconds))

    // Total persistence cost: the add plus waiting for the background write to land.
    let saveFlush = sample(runs, prepare: {
        if let id = added {
            inbox.remove(id)
            inbox.flush()
            added = nil
        }
    }, run: { _ in
        counter += 1
        added = inbox.add(text: "bench add \(counter) " + filler)?.id
        inbox.flush()
        return 1
    })
    if let id = added { inbox.remove(id) }
    inbox.flush()
    scenarios.append(ScenarioResult(name: "save-flush", milliseconds: saveFlush.milliseconds))

    // A pasted 2 MB text in other scripts. Its search key is built in the background, not inside `add`.
    let large = String(repeating: "Привет мир 日本語のテキスト 😀 ", count: 40_000)
    var addedLarge: UUID?
    var largeCounter = 0
    let addLarge = sample(runs, prepare: {
        if let id = addedLarge {
            inbox.remove(id)
            inbox.flush()
            addedLarge = nil
        }
    }, run: { _ in
        largeCounter += 1
        addedLarge = inbox.add(text: "bench large \(largeCounter) " + large)?.id
        return 1
    })
    if let id = addedLarge { inbox.remove(id) }
    inbox.flush()
    scenarios.append(ScenarioResult(name: "add-large-mixed", milliseconds: addLarge.milliseconds))

    let queries = SearchQueries(options.corpus)
    for (name, query) in queries.warm {
        let result = sample(runs, prepare: { () }, run: { _ in inbox.search(query).count })
        scenarios.append(ScenarioResult(name: name, milliseconds: result.milliseconds, matches: result.count))
    }
    // A fresh inbox has no search keys yet. Only the main-actor work of the first search is timed; the background
    // key build runs beside it, and its install waits for the main actor, which this loop never yields.
    for (name, query) in queries.cold {
        var deferred = 0
        var last: Inbox?
        let cold = sample(runs, prepare: { () -> Inbox in
            settle(&last)
            let fresh = Inbox(directory: directory, limit: limit)
            last = fresh
            return fresh
        }, run: { fresh in
            let found = fresh.search(query).count
            deferred = fresh.deferredSearchItems
            return found
        })
        settle(&last)
        scenarios.append(ScenarioResult(
            name: name, milliseconds: cold.milliseconds, matches: cold.count, deferred: deferred
        ))
    }
    // Time from the end of `Inbox.init` until the background build has installed every key.
    let warmup = sample(runs, prepare: { Inbox(directory: directory, limit: limit) }, run: { fresh in
        while !fresh.isSearchReady { RunLoop.main.run(mode: .default, before: .now + 0.0005) }
        return 1
    })
    scenarios.append(ScenarioResult(name: "search-warmup", milliseconds: warmup.milliseconds))

    let model = ClipboardModel(inbox: inbox)
    model.query = queries.results
    let results = sample(runs, prepare: { () }, run: { _ in model.results.count })
    scenarios.append(ScenarioResult(name: "results", milliseconds: results.milliseconds, matches: results.count))

    guard let picture = inbox.items.first(where: { $0.fileName != nil }) else { throw BenchError.noImages }
    // A new model per run has an empty image cache, so every run is a cache miss.
    let opened = sample(runs, prepare: { ClipboardModel(inbox: inbox) }, run: { model in
        model.image(for: picture) == nil ? 0 : 1
    })
    scenarios.append(ScenarioResult(name: "thumbnail-open", milliseconds: opened.milliseconds))
    // Drawing forces the pixel decode that a row pays on first paint, so this is the cost the list shows.
    let drawn = sample(runs, prepare: { ClipboardModel(inbox: inbox) }, run: { model in
        guard let image = model.image(for: picture) else { return 0 }
        return drawThumbnail(image)
    })
    scenarios.append(ScenarioResult(name: "thumbnail-draw", milliseconds: drawn.milliseconds))

    return SizeResult(items: count, historyKB: Double(bytes) / 1024, scenarios: scenarios)
}

/// Waits until `inbox`'s background search build is done, then frees it.
@MainActor
private func settle(_ inbox: inout Inbox?) {
    while let current = inbox, !current.isSearchReady { RunLoop.main.run(mode: .default, before: .now + 0.0005) }
    inbox = nil
}

/// Untimed runs before the timed ones. Three, so caches and the allocator settle before the first sample.
private let warmUpRuns = 3

/// The row thumbnail frame in points, from `ClipboardListView` (`maxWidth: 200`, `imageRowHeight - 10`).
private let rowThumbnailPoints = CGSize(width: 200, height: 40)

/// Draws `image` aspect-fit into the row frame at 2x and returns 1. Drawing decodes the pixels.
@MainActor
private func drawThumbnail(_ image: NSImage) -> Int {
    let canvas = CGSize(width: rowThumbnailPoints.width * 2, height: rowThumbnailPoints.height * 2)
    guard let context = CGContext(
        data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return 0 }
    let source = image.size
    let scale = min(canvas.width / source.width, canvas.height / source.height)
    let fitted = CGSize(width: source.width * scale, height: source.height * scale)
    let origin = CGPoint(x: (canvas.width - fitted.width) / 2, y: (canvas.height - fitted.height) / 2)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    image.draw(in: CGRect(origin: origin, size: fitted))
    NSGraphicsContext.restoreGraphicsState()
    return 1
}

/// Runs `run` `warmUpRuns` times untimed, then `iterations` timed times. `prepare` runs before each run, outside the timer.
/// Returns the timed runs in milliseconds and the count from the last run.
@MainActor
private func sample<Input>(
    _ iterations: Int, prepare: () -> Input, run: (Input) -> Int
) -> (milliseconds: [Double], count: Int) {
    var milliseconds: [Double] = []
    var count = 0
    for index in 0..<(warmUpRuns + iterations) {
        let input = prepare()
        let start = ContinuousClock.now
        count = run(input)
        let elapsed = ContinuousClock.now - start
        if index >= warmUpRuns { milliseconds.append(millis(elapsed)) }
    }
    return (milliseconds, count)
}

private func millis(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}

private func fileSize(_ url: URL) throws -> Int {
    try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
}

/// The queries each corpus times, as (scenario name, query).
private struct SearchQueries {
    let warm: [(String, String)]
    let cold: [(String, String)]
    /// The query for the `results` scenario.
    let results: String

    init(_ corpus: Corpus) {
        switch corpus {
        case .ascii:
            warm = [
                ("search-common", "the"), ("search-rare", "quartz"), ("search-none", "zzqxv"),
                ("search-accent-on-ascii", "ação"),
            ]
            cold = [("search-cold", "the")]
            results = "the"
        case .pt:
            warm = [
                ("search-pt-common", "de"), ("search-pt-rare", "quartzo"), ("search-pt-none", "zzqxv"),
                ("search-pt-accent", "ação"), ("search-pt-accent2", "Reunião"),
                ("search-pt-digit", "9999"), ("search-pt-digit2", "v2"),
                ("search-pt-mixed", "テキスト"), ("search-pt-emoji", "😀"),
            ]
            cold = [
                ("search-pt-cold-rare", "quartzo"), ("search-pt-cold-accent", "ação"),
                ("search-pt-cold-digit", "9999"), ("search-pt-cold-mixed", "テキスト"),
            ]
            results = "de"
        case .mixed:
            warm = [
                ("search-mixed-cyrillic", "привет"), ("search-mixed-japanese", "テキスト"),
                ("search-mixed-arabic", "مرحبا"), ("search-mixed-hindi", "नमस्ते"), ("search-mixed-emoji", "😀"),
                ("search-mixed-none", "zzqxv"),
            ]
            cold = [
                ("search-mixed-cold-cyrillic", "привет"), ("search-mixed-cold-japanese", "テキスト"),
                ("search-mixed-cold-arabic", "مرحبا"), ("search-mixed-cold-hindi", "नमस्ते"),
                ("search-mixed-cold-emoji", "😀"),
            ]
            results = "привет"
        }
    }
}
