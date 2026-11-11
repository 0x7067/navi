import Foundation

// Usage:
//   swift run -c release history-bench [--sizes 200,1000,5000] [--iterations 20] [--seed 42] [--corpus ascii|mixed] [--save] [--json]
//
// --sizes       history sizes to seed and time (default: 200,1000,5000)
// --iterations  timed runs per scenario at 1,000 items and up, after three discarded warm-up runs.
//               Smaller sizes get iterations × max(1, 1000 / size) timed runs (default: 20)
// --seed        seed for the synthetic history (default: 42)
// --corpus      language of the seeded text: ascii (default) or mixed (accented Latin, non-Latin scripts and emoji)
// --save        write the report to Bench/results/<date>-<commit>.json
// --json        print the report as JSON instead of a table

let packageRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

do {
    let options = try BenchOptions(arguments: Array(CommandLine.arguments.dropFirst()))
    let report = try runBench(options, packageRoot: packageRoot)
    if options.json {
        print(try report.json())
    } else {
        print(report.table())
    }
    if options.save {
        let url = try report.save(in: packageRoot)
        if !options.json { print("Saved \(url.lastPathComponent)") }
    }
} catch {
    print("history-bench: \(error)")
    exit(1)
}
