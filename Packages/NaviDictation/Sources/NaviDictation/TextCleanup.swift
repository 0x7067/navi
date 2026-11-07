import Foundation

/// Rule-based cleanup for dictated text. Pure and deterministic.
///
/// It removes clear filler words, fixes spacing and capitals, and adds a final period to sentences.
/// It is careful: "like" and "you know" go away only when commas or a sentence start mark them as
/// filler. "I like pizza" and "Do you know the way?" stay as they are.
public enum TextCleanup {
    /// Words that people repeat by stutter ("I I think", "the the"). Words like "that" and "had"
    /// are not in the list, because they repeat on purpose ("that that", "had had").
    private static let stutterWords = ["i", "a", "the", "to", "and", "so", "it", "we", "in", "of"]

    /// Texts with at least this many words get a final period when they have no end punctuation.
    private static let finalPeriodMinimumWords = 3

    public static func clean(_ input: String, addsFinalPeriod: Bool = true) -> String {
        var text = input.replacingOccurrences(of: "\n", with: " ")
        text = removeFillers(from: text)
        text = removeStutters(from: text)
        text = tidySpacingAndPunctuation(text)
        text = capitalize(text)
        if addsFinalPeriod { text = addFinalPeriod(to: text) }
        return text
    }

    // MARK: Steps

    static func removeFillers(from text: String) -> String {
        var text = text
        // Sounds: "um", "uh", "er", "hmm", with the commas around them.
        text = replace(#"(?:,\s*)?\b(?:um+|uh+|erm|er|hmm+)\b(?:\s*,)?"#, in: text, with: " ")
        // ", like," and ", you know," in the middle of a sentence.
        text = replace(#",\s*(?:like|you know)\s*,"#, in: text, with: " ")
        // "Like, ..." and "You know, ..." at the start of the text or of a sentence.
        text = replace(#"(^|[.!?]\s+)(?:like|you know),\s*"#, in: text, with: "$1")
        return text
    }

    static func removeStutters(from text: String) -> String {
        let words = stutterWords.joined(separator: "|")
        return replace(#"\b(\#(words))(?:\s+\1\b)+"#, in: text, with: "$1")
    }

    static func tidySpacingAndPunctuation(_ text: String) -> String {
        var text = text
        text = replace(#"\s+"#, in: text, with: " ")
        // No space before , . ? ! ; :
        text = replace(#"\s+([,.?!;:])"#, in: text, with: "$1")
        // Repeated commas, and a comma that now sits next to other punctuation.
        text = replace(#",(?:\s*,)+"#, in: text, with: ",")
        text = replace(#"([.?!]),"#, in: text, with: "$1")
        // A comma at the very start.
        text = replace(#"^[\s,;:]+"#, in: text, with: "")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Capital letter at the start and after . ? ! and a space. Also "i", "i'm", "i'll", "i've", "i'd" to "I".
    /// A dot with no space after it ("example.com", "3.5") does not start a sentence. Neither does "i.e." or "e.g.".
    static func capitalize(_ text: String) -> String {
        let text = replace(#"(?<![\w.])i(?=$|[\s,?!;:'’]|\.(?!\w))"#, in: text, with: "I")
        var result = ""
        var capitalizeNext = true
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            if capitalizeNext, character.isLetter {
                result.append(contentsOf: character.uppercased())
                capitalizeNext = false
                continue
            }
            result.append(character)
            if ".?!".contains(character) {
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let endsAbbreviation = result.lowercased().hasSuffix("i.e.") || result.lowercased().hasSuffix("e.g.")
                if (next == nil || next?.isWhitespace == true), !endsAbbreviation { capitalizeNext = true }
            } else if !character.isWhitespace, !character.isPunctuation || character == "," {
                capitalizeNext = false
            }
        }
        return result
    }

    static func addFinalPeriod(to text: String) -> String {
        guard let last = text.last, last.isLetter || last.isNumber else { return text }
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        return wordCount >= finalPeriodMinimumWords ? text + "." : text
    }

    // MARK: Helpers

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        text.replacingOccurrences(
            of: pattern, with: template, options: [.regularExpression, .caseInsensitive],
            range: text.startIndex..<text.endIndex
        )
    }
}
