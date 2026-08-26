import XCTest
@testable import MindLocal

/// Chunking is what makes a spoken reply start quickly instead of after a
/// pause. It's also audible when it's wrong: a split in the wrong place lands
/// as a pause where no pause belongs.
final class SpeechChunkerTests: XCTestCase {

    private let chunker = SpeechChunker()

    // MARK: - Nothing to say

    func test_emptyText_producesNoChunks() {
        XCTAssertTrue(chunker.chunks(from: "").isEmpty)
        XCTAssertTrue(chunker.chunks(from: "   \n  ").isEmpty)
    }

    func test_punctuationOnly_isStillSpoken() {
        // NLTokenizer finds no sentences here. Dropping the text silently would
        // leave the caller's isSpeaking stuck on, so it comes through verbatim.
        XCTAssertEqual(chunker.chunks(from: "?!"), ["?!"])
    }

    // MARK: - Short input stays whole

    func test_singleSentence_isOneChunk() {
        let text = "You decided to take the offer."
        XCTAssertEqual(chunker.chunks(from: text), [text])
    }

    func test_shortSentences_areMergedIntoOneChunk() {
        // Each is far below the cap; synthesising them separately would add
        // seams and per-chunk overhead for no latency benefit.
        let chunks = chunker.chunks(from: "You slept badly. You skipped lunch. You said yes anyway.")
        XCTAssertEqual(chunks.count, 1)
    }

    // MARK: - Boundaries the tokenizer has to get right

    func test_abbreviationDoesNotSplitTheSentence() {
        // A regex on "." breaks "Dr." and turns one sentence into two pauses.
        let text = "Dr. Patel suggested waiting. You agreed."
        let chunks = chunker.chunks(from: text)
        XCTAssertEqual(chunks.count, 1, "abbreviation should not create a chunk boundary")
        XCTAssertTrue(chunks[0].contains("Dr. Patel"))
    }

    func test_decimalNumberDoesNotSplitTheSentence() {
        let chunks = chunker.chunks(from: "You slept 6.5 hours and still felt fine.")
        XCTAssertEqual(chunks.count, 1)
    }

    // MARK: - Long input

    func test_noChunkExceedsTheMaximum() {
        let long = String(repeating: "This is a sentence about a decision you made. ", count: 40)
        for chunk in chunker.chunks(from: long) {
            XCTAssertLessThanOrEqual(chunk.count, chunker.maxCharacters, "chunk over cap: \(chunk)")
        }
    }

    func test_longSentence_splitsAtClauseBoundaries() {
        // One sentence, no full stops to split on. It has to break at commas,
        // where a pause sounds intended rather than accidental.
        let runOn = "You considered the offer carefully, "
            + String(repeating: "weighing the salary against the commute and the team, ", count: 8)
            + "and then you said yes."
        let chunks = chunker.chunks(from: runOn)

        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, chunker.maxCharacters)
        }
        // Punctuation stays attached so the synthesiser still inflects for it.
        XCTAssertTrue(chunks.dropLast().allSatisfy { $0.hasSuffix(",") || $0.hasSuffix(".") })
    }

    func test_runOnWithNoPunctuation_splitsOnWordsNotMidWord() {
        let words = Array(repeating: "decision", count: 120).joined(separator: " ")
        let chunks = chunker.chunks(from: words)

        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, chunker.maxCharacters)
            // Every token must still be a whole word.
            XCTAssertTrue(chunk.split(separator: " ").allSatisfy { $0 == "decision" },
                          "split landed mid-word: \(chunk)")
        }
    }

    // MARK: - Nothing is lost

    func test_allWordsSurviveChunking() {
        let text = """
            You have been circling this for three weeks. The salary is better, \
            but the commute is worse and you already said the commute was what \
            broke you last time. Dr. Patel's advice was to sleep on it. You \
            slept 6.5 hours and woke up still unsure.
            """
        let rejoined = chunker.chunks(from: text).joined(separator: " ")
        XCTAssertEqual(rejoined.split(separator: " ").count,
                       text.split(whereSeparator: \.isWhitespace).count,
                       "chunking dropped or duplicated words")
    }

    // MARK: - Runt merging

    func test_shortTrailingChunk_isMergedBack() {
        // A long sentence forces a boundary, then a two-word sentence follows.
        // Speaking "Yes." alone costs a full synthesis pass and sounds clipped.
        let text = String(repeating: "You weighed the offer against the commute again. ", count: 5) + "You agreed."
        let chunks = chunker.chunks(from: text)
        XCTAssertFalse(chunks.contains("You agreed."),
                       "runt tail should have been folded into the previous chunk")
    }

    func test_customLimitsAreRespected() {
        var tight = SpeechChunker()
        tight.maxCharacters = 60
        tight.minCharacters = 10
        let chunks = tight.chunks(from: String(repeating: "A short sentence here. ", count: 10))
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks { XCTAssertLessThanOrEqual(chunk.count, 60) }
    }
}
