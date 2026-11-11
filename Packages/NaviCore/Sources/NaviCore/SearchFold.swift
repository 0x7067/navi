import Foundation
import os

/// Builds the search key of a text: the bytes of `string.folding(options: [.caseInsensitive, .diacriticInsensitive,
/// .widthInsensitive], locale: nil)`, byte for byte, without calling it for every text.
///
/// The fold is the same in every locale. Case, accents and character width are ignored (`ação` becomes `acao`,
/// `ß` becomes `ss`, fullwidth `Ａ` becomes `a`), and a combining mark with no letter before it is kept.
/// ASCII is lowercased eight bytes at a time. Other characters come from a table for U+0080 to U+02FF or a
/// cache filled by the system fold, one character (with the marks after it) at a time.
enum SearchFold {
    /// The system fold. `fold(_:)` must return the same bytes for every string; the tests check it.
    static func reference(_ string: String) -> [UInt8] {
        Array(string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).utf8)
    }

    /// The search key of `string`.
    static func fold(_ string: String) -> [UInt8] {
        var string = string
        return string.withUTF8 { source in
            asciiFold(source) ?? generalFold(source)
        }
    }

    // MARK: Caches

    private struct Entry: Sendable {
        let bytes: [UInt8]
        let isMark: Bool
    }

    private struct SystemFolds: Sendable {
        var scalars: [UInt32: Entry] = [:]
        var clusters: [[UInt8]: [UInt8]] = [:]
    }

    private static let systemFolds = OSAllocatedUnfairLock(initialState: SystemFolds())

    /// The caches are cleared when they reach these sizes, so odd text (such as stacks of combining marks)
    /// cannot grow them without limit. Clusters longer than `longestCachedCluster` bytes are not cached.
    static let maxCachedScalars = 16384
    static let maxCachedClusters = 2048
    static let longestCachedCluster = 64

    /// How many entries the caches hold, for tests.
    static var cacheSizes: (scalars: Int, clusters: Int) {
        systemFolds.withLock { ($0.scalars.count, $0.clusters.count) }
    }

    /// Folds for U+0080 to U+02FF as rows of eight bytes: the length, then up to seven bytes. None of these is a
    /// combining mark. Allocated once and never freed.
    nonisolated(unsafe) private static let latin: UnsafeMutablePointer<UInt8> = {
        let table = UnsafeMutablePointer<UInt8>.allocate(capacity: 0x280 * 8)
        table.initialize(repeating: 0, count: 0x280 * 8)
        for value in 0x80..<0x300 {
            let bytes = Unicode.Scalar(value).map { reference(String($0)) } ?? []
            precondition(bytes.count <= 7)
            let row = table + (value - 0x80) * 8
            row[0] = UInt8(bytes.count)
            for (offset, byte) in bytes.enumerated() { row[1 + offset] = byte }
        }
        return table
    }()

    private static func isMarkCategory(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }

    /// The fold and mark flag of a scalar from U+0300 up, from the cache or the system fold.
    private static func entry(_ value: UInt32) -> Entry {
        if let cached = systemFolds.withLock({ $0.scalars[value] }) { return cached }
        let scalar = Unicode.Scalar(value) ?? "\u{FFFD}"
        let made = Entry(bytes: reference(String(scalar)), isMark: isMarkCategory(scalar))
        systemFolds.withLock {
            if $0.scalars.count >= maxCachedScalars { $0.scalars.removeAll() }
            $0.scalars[value] = made
        }
        return made
    }

    /// The system fold of a letter and the marks after it.
    /// Keyed by the exact bytes, because equal-looking strings (canonically equivalent ones) compare equal as keys.
    private static func clusterFold(_ cluster: [UInt8]) -> [UInt8] {
        if let cached = systemFolds.withLock({ $0.clusters[cluster] }) { return cached }
        let made = reference(String(decoding: cluster, as: UTF8.self))
        guard cluster.count <= longestCachedCluster else { return made }
        systemFolds.withLock {
            if $0.clusters.count >= maxCachedClusters { $0.clusters.removeAll() }
            $0.clusters[cluster] = made
        }
        return made
    }

    // MARK: ASCII

    private static let high: UInt64 = 0x8080_8080_8080_8080
    private static let ones: UInt64 = 0x0101_0101_0101_0101

    /// Lowercases eight ASCII bytes at once. The high bit of each intermediate byte says whether it is at
    /// least A, and at least [.
    @inline(__always)
    private static func lowercased(_ word: UInt64) -> UInt64 {
        let atLeastA = word &+ (0x80 - 0x41) &* ones
        let atLeastBracket = word &+ (0x80 - 0x5B) &* ones
        return word | ((atLeastA & ~atLeastBracket & high) >> 2)
    }

    /// Lowercases ASCII text eight bytes at a time. Nil when any byte is not ASCII.
    private static func asciiFold(_ source: UnsafeBufferPointer<UInt8>) -> [UInt8]? {
        guard let base = source.baseAddress else { return [] }
        var isASCII = true
        let bytes = [UInt8](unsafeUninitializedCapacity: source.count) { out, count in
            var index = 0
            while index + 8 <= source.count {
                let word = UnsafeRawPointer(base + index).loadUnaligned(as: UInt64.self)
                if word & high != 0 {
                    isASCII = false
                    return
                }
                UnsafeMutableRawPointer(out.baseAddress! + index).storeBytes(of: lowercased(word), as: UInt64.self)
                index += 8
            }
            while index < source.count {
                let byte = base[index]
                if byte >= 0x80 {
                    isASCII = false
                    return
                }
                out[index] = byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte
                index += 1
            }
            count = source.count
        }
        return isASCII ? bytes : nil
    }

    // MARK: Everything else

    /// A growable byte buffer that is written through a pointer.
    private struct Output: ~Copyable {
        private(set) var count = 0
        private var capacity: Int
        private var storage: UnsafeMutablePointer<UInt8>

        init(capacity: Int) {
            self.capacity = capacity
            storage = .allocate(capacity: capacity)
        }

        deinit { storage.deallocate() }

        mutating func reserve(_ extra: Int) {
            guard count + extra > capacity else { return }
            let bigger = UnsafeMutablePointer<UInt8>.allocate(capacity: max(capacity * 2, count + extra))
            bigger.update(from: storage, count: count)
            storage.deallocate()
            storage = bigger
            capacity = max(capacity * 2, count + extra)
        }

        /// Appends a row of the Latin table: the length, then the bytes.
        mutating func append(row: UnsafeMutablePointer<UInt8>) {
            reserve(8)
            let length = Int(row[0])
            for offset in 0..<length { storage[count + offset] = row[1 + offset] }
            count += length
        }

        mutating func append(_ byte: UInt8) {
            reserve(1)
            storage[count] = byte
            count += 1
        }

        mutating func append(contentsOf bytes: [UInt8]) {
            reserve(bytes.count)
            for byte in bytes {
                storage[count] = byte
                count += 1
            }
        }

        mutating func append(contentsOf bytes: UnsafeBufferPointer<UInt8>) {
            reserve(bytes.count)
            for byte in bytes {
                storage[count] = byte
                count += 1
            }
        }

        /// Appends eight lowercased ASCII bytes with one store.
        mutating func appendWord(_ word: UInt64) {
            reserve(8)
            UnsafeMutableRawPointer(storage + count).storeBytes(of: word, as: UInt64.self)
            count += 8
        }

        mutating func truncate(to length: Int) { count = length }

        func bytes() -> [UInt8] { Array(UnsafeBufferPointer(start: storage, count: count)) }
    }

    /// Decodes the scalar that starts at `index`. The text is valid UTF-8.
    @inline(__always)
    private static func decode(_ source: UnsafeBufferPointer<UInt8>, _ index: Int) -> (value: UInt32, length: Int) {
        let byte = source[index]
        if byte < 0xE0 { return (UInt32(byte & 0x1F) << 6 | UInt32(source[index + 1] & 0x3F), 2) }
        if byte < 0xF0 {
            let value = UInt32(byte & 0x0F) << 12 | UInt32(source[index + 1] & 0x3F) << 6 | UInt32(source[index + 2] & 0x3F)
            return (value, 3)
        }
        let value = UInt32(byte & 0x07) << 18 | UInt32(source[index + 1] & 0x3F) << 12
            | UInt32(source[index + 2] & 0x3F) << 6 | UInt32(source[index + 3] & 0x3F)
        return (value, 4)
    }

    /// True for a scalar from U+0300 up that attaches to the one before it.
    @inline(__always)
    private static func isMark(_ value: UInt32) -> Bool {
        if value < 0x300 { return false }
        if value <= 0x36F { return true }
        // Halfwidth voicing marks join the katakana before them when folded for width.
        if value == 0xFF9E || value == 0xFF9F { return true }
        // Ideographs and Hangul syllables are not marks and fold to themselves.
        if (value >= 0x3400 && value <= 0x9FFF) || (value >= 0xAC00 && value <= 0xD7A3) { return false }
        return entry(value).isMark
    }

    /// Scalars whose system fold depends on the text around them in ways the table does not model: some
    /// spaces and brackets, the zero-width non-joiner, CJK compatibility ideographs, emoji skin tones, tags.
    /// A text with one of these is folded by the system as a whole.
    private static func isHard(_ value: UInt32) -> Bool {
        switch value {
        case 0x2002...0x2003, 0x200C, 0x3008...0x3009, 0xF900...0xFAFF, 0x113C5, 0x16121, 0x1F3FB...0x1F3FF,
             0x22844, 0x2284A, 0x233D5, 0x242EE, 0x25249, 0x25CD0, 0x27ED3, 0x2F800...0x2FA1F, 0xE0020...0xE007F:
            true
        default:
            false
        }
    }

    private static func generalFold(_ source: UnsafeBufferPointer<UInt8>) -> [UInt8] {
        let count = source.count
        var output = Output(capacity: count + count / 2 + 16)
        var index = 0
        // Where the last letter starts in the text and in the output, so marks after it can fold with it.
        var baseSource = 0
        var baseOutput = 0
        var hasBase = false
        // The end of the last non-ASCII character, in the text and the output. The ASCII after it is copied as is.
        var plainSource = 0
        var plainOutput = 0
        // The last place where a text can be cut: just after a space that is followed by ASCII. A text that needs
        // the system fold is folded from here to the next such place, not as a whole.
        var cutSource = 0
        var cutOutput = 0
        while index < count {
            if index + 8 <= count {
                let word = UnsafeRawPointer(source.baseAddress! + index).loadUnaligned(as: UInt64.self)
                if word & high == 0 {
                    output.appendWord(lowercased(word))
                    baseSource = index + 7
                    baseOutput = output.count - 1
                    hasBase = true
                    index += 8
                    continue
                }
            }
            let byte = source[index]
            if byte < 0x80 {
                baseSource = index
                baseOutput = output.count
                hasBase = true
                output.append(byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte)
                index += 1
                continue
            }
            // Look back through the ASCII since the last non-ASCII character for a place to cut.
            var back = index - 2
            while back >= plainSource {
                if source[back] == 0x20 {
                    cutSource = back + 1
                    cutOutput = plainOutput + (back + 1 - plainSource)
                    break
                }
                back -= 1
            }
            let (value, length) = decode(source, index)
            var needsSystem = value >= 0x2002 && isHard(value)
            if !needsSystem {
                if value < 0x300 {
                    baseSource = index
                    baseOutput = output.count
                    hasBase = true
                    let row = latin + (Int(value) - 0x80) * 8
                    output.append(row: row)
                    index += length
                } else if isMark(value) {
                    let end = foldMarks(source, from: index, into: &output, hasBase: hasBase, baseSource: baseSource, baseOutput: baseOutput)
                    if end < 0 {
                        needsSystem = true
                    } else {
                        index = end
                        hasBase = false
                    }
                } else if (value >= 0x3400 && value <= 0x9FFF) || (value >= 0xAC00 && value <= 0xD7A3) {
                    baseSource = index
                    baseOutput = output.count
                    hasBase = true
                    output.append(contentsOf: UnsafeBufferPointer(rebasing: source[index..<index + length]))
                    index += length
                } else {
                    baseSource = index
                    baseOutput = output.count
                    hasBase = true
                    output.append(contentsOf: entry(value).bytes)
                    index += length
                }
            }
            if needsSystem {
                var end = index
                while end < count, !(source[end] == 0x20 && end + 1 < count && source[end + 1] < 0x80) { end += 1 }
                end = min(end + 1, count)
                output.truncate(to: cutOutput)
                let segment = String(decoding: UnsafeBufferPointer(rebasing: source[cutSource..<end]), as: UTF8.self)
                output.append(contentsOf: reference(segment))
                index = end
                hasBase = false
                cutSource = end
                cutOutput = output.count
            }
            plainSource = index
            plainOutput = output.count
        }
        return output.bytes()
    }

    /// Folds the run of marks that starts at `start` together with the letter before it, and returns where the run
    /// ends. Returns -1 for marks above U+036F (Devanagari, Arabic, kana voicing), whose system fold depends on
    /// the text around them; the caller folds the whole text with the system.
    private static func foldMarks(
        _ source: UnsafeBufferPointer<UInt8>, from start: Int, into output: inout Output,
        hasBase: Bool, baseSource: Int, baseOutput: Int
    ) -> Int {
        var end = start
        while end < source.count, source[end] >= 0x80 {
            let (value, length) = decode(source, end)
            guard isMark(value) else { break }
            if value > 0x36F { return -1 }
            end += length
        }
        guard hasBase else {
            output.append(contentsOf: clusterFold(Array(UnsafeBufferPointer(rebasing: source[start..<end]))))
            return end
        }
        let base = source[baseSource]
        // The system fold drops U+0300 to U+036F after an ASCII letter, and the letter is already written.
        if base < 0x80, (base | 0x20) >= 0x61, (base | 0x20) <= 0x7A { return end }
        output.truncate(to: baseOutput)
        output.append(contentsOf: clusterFold(Array(UnsafeBufferPointer(rebasing: source[baseSource..<end]))))
        return end
    }
}
