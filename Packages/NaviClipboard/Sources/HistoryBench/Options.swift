import Foundation

/// Command-line options for `history-bench`.
struct BenchOptions {
    var sizes = [200, 1000, 5000]
    var iterations = 20
    var seed: UInt64 = 42
    var save = false
    var json = false
    var corpus = Corpus.ascii

    init(arguments: [String]) throws {
        var remaining = arguments[...]
        while let flag = remaining.popFirst() {
            switch flag {
            case "--sizes":
                sizes = try Self.value(flag, &remaining).split(separator: ",").map { try Self.positive(String($0), flag) }
            case "--iterations":
                iterations = try Self.positive(Self.value(flag, &remaining), flag)
            case "--seed":
                let text = try Self.value(flag, &remaining)
                guard let number = UInt64(text) else { throw BenchError.usage("--seed needs a whole number, got \(text)") }
                seed = number
            case "--corpus":
                let text = try Self.value(flag, &remaining)
                guard let chosen = Corpus(rawValue: text) else {
                    throw BenchError.usage("--corpus needs ascii, pt or mixed, got \(text)")
                }
                corpus = chosen
            case "--save": save = true
            case "--json": json = true
            default: throw BenchError.usage("unknown option \(flag)")
            }
        }
    }

    private static func value(_ flag: String, _ remaining: inout ArraySlice<String>) throws -> String {
        guard let next = remaining.popFirst() else { throw BenchError.usage("\(flag) needs a value") }
        return next
    }

    private static func positive(_ text: String, _ flag: String) throws -> Int {
        guard let number = Int(text), number > 0 else {
            throw BenchError.usage("\(flag) needs positive whole numbers, got \(text)")
        }
        return number
    }
}

/// The language of the seeded text items.
enum Corpus: String {
    /// English words, all ASCII.
    case ascii
    /// Portuguese words; about 60% of text items contain accented words.
    case pt
    /// Cyrillic, Japanese, Arabic, Hindi and emoji-heavy text items, one script per item.
    case mixed
}

/// Errors that stop the benchmark with a message.
enum BenchError: Error, CustomStringConvertible {
    case usage(String)
    case render
    case noImages
    case seeding(expected: Int, found: Int)

    var description: String {
        switch self {
        case .usage(let message): message
        case .render: "could not render a test picture"
        case .noImages: "the seeded history has no image items"
        case .seeding(let expected, let found): "seeded \(found) items, expected \(expected)"
        }
    }
}
