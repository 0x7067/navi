import DictationEval
import Testing

@Suite("Scoring")
struct ScoringTests {
    @Test("words ignore case and punctuation but keep contractions and numbers")
    func words() {
        #expect(Scoring.words("Hey, I don't know! It's 3.5 GB.") == ["hey", "i", "don't", "know", "it's", "3.5", "gb"])
    }

    @Test("word error rate counts edits per reference word")
    func wordErrorRate() {
        #expect(Scoring.wordErrorRate("meet at three", reference: "Meet at 3.") == 1.0 / 3.0)
        #expect(Scoring.wordErrorRate("Meet at 3", reference: "meet at 3.") == 0)
        #expect(Scoring.wordErrorRate("", reference: "a b") == 1)
    }

    @Test("a clean result passes; a filler left behind fails")
    func passAndFillers() {
        let benchCase = BenchCase(id: "f1", category: "filler", input: "um so yeah", expected: ["So yeah."])
        #expect(Scoring.score(benchCase, output: "So yeah.").passed)
        #expect(Scoring.score(benchCase, output: "So yeah.").exact)
        let left = Scoring.score(benchCase, output: "Um, so yeah.")
        #expect(!left.passed)
        #expect(left.fillersLeft == 1)
    }

    @Test("made-up words are words in neither the input nor the expected result")
    func inventedWords() {
        let benchCase = BenchCase(id: "c1", category: "correction", input: "meet at 2 actually 3", expected: ["Meet at 3."])
        let score = Scoring.score(benchCase, output: "Let's meet at 3 tomorrow.")
        #expect(score.inventedWords == ["let's", "tomorrow"])
    }

    @Test("the closest expected result is used")
    func alternatives() {
        let benchCase = BenchCase(id: "a1", category: "list", input: "x", expected: ["One two.", "1. One\n2. Two"])
        #expect(Scoring.score(benchCase, output: "1. One\n2. Two").exact)
    }

    @Test("summary rates and nearest-rank percentiles")
    func summary() {
        let scores = (1 ... 10).map { index in
            CaseScore(
                id: "\(index)", category: "c", output: "", passed: index <= 7, exact: false, wordAccuracy: 1,
                fillersLeft: 0, inventedWords: [], milliseconds: Double(index)
            )
        }
        let summary = Summary(name: "c", scores: scores)
        #expect(summary.passRate == 0.7)
        #expect(summary.p50Milliseconds == 5)
        #expect(summary.p95Milliseconds == 10)
    }
}
