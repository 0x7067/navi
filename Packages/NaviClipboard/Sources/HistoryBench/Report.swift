import Foundation

/// Timings for one scenario, in milliseconds over the timed runs.
struct ScenarioResult: Codable {
    let name: String
    let medianMs: Double
    let p95Ms: Double
    let minMs: Double
    /// Items the scenario returned on its last run. Nil where that does not apply.
    let matches: Int?

    init(name: String, milliseconds: [Double], matches: Int? = nil) {
        let sorted = milliseconds.sorted()
        self.name = name
        medianMs = Statistics.median(sorted)
        p95Ms = Statistics.percentile(sorted, 0.95)
        minMs = sorted.first ?? 0
        self.matches = matches
    }
}

/// All scenarios for one history size.
struct SizeResult: Codable {
    let items: Int
    let historyKB: Double
    let scenarios: [ScenarioResult]
}

/// The machine a report was measured on.
struct Machine: Codable {
    let cpu: String
    let macOS: String
}

/// One full run of `history-bench`.
struct BenchReport: Codable {
    let recorded: String
    let commit: String
    let machine: Machine
    let seed: UInt64
    let iterations: Int
    let sizes: [SizeResult]

    /// The report as pretty-printed JSON.
    func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    /// Writes the JSON to `Bench/results/<date>-<commit>.json` under `packageRoot`.
    func save(in packageRoot: URL) throws -> URL {
        let folder = packageRoot.appending(path: "Bench/results", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Colons are not allowed in some file systems; the existing results use dots.
        let stamp = String(recorded.replacingOccurrences(of: ":", with: ".").dropLast())
        let url = folder.appending(path: "\(stamp)-\(commit).json")
        try (json() + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A fixed-width table, one block per size.
    func table() -> String {
        var lines = [
            "History benchmark · commit \(commit) · \(machine.cpu) · macOS \(machine.macOS) · seed \(seed) · \(iterations) runs",
        ]
        for size in sizes {
            lines.append("")
            lines.append("\(size.items) items · history.json \(String(format: "%.0f", size.historyKB)) KB")
            lines.append(Self.row("scenario", "median ms", "p95 ms", "min ms", "matches", left: true))
            for scenario in size.scenarios {
                lines.append(Self.row(
                    scenario.name,
                    Self.ms(scenario.medianMs), Self.ms(scenario.p95Ms), Self.ms(scenario.minMs),
                    scenario.matches.map(String.init) ?? "-"
                ))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func row(_ name: String, _ median: String, _ p95: String, _ minimum: String, _ matches: String, left: Bool = false) -> String {
        [
            pad(name, 16, alignRight: !left), pad(median, 11), pad(p95, 11), pad(minimum, 11), pad(matches, 9),
        ].joined()
    }

    private static func pad(_ text: String, _ width: Int, alignRight: Bool = true) -> String {
        let spaces = String(repeating: " ", count: max(width - text.count, 0))
        return alignRight ? spaces + text : text + spaces
    }

    private static func ms(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

/// Median and percentiles of timing samples.
enum Statistics {
    /// Median of sorted, non-empty samples. Averages the two middle values for an even count.
    static func median(_ sorted: [Double]) -> Double {
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Nearest-rank percentile of sorted, non-empty samples.
    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        let rank = Int((fraction * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }
}

/// The value of a sysctl string, such as `machdep.cpu.brand_string`.
func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(decoding: buffer.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

/// The short hash of HEAD in the repository at `directory`, or "unknown".
func gitShortCommit(in directory: URL) -> String {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/git")
    process.arguments = ["-C", directory.path, "rev-parse", "--short", "HEAD"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return "unknown" }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? "unknown" : text
}
