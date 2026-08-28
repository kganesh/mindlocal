import XCTest
@testable import MindLocal

/// Two failure modes matter here and they pull against each other: leaving
/// markup in means the synthesiser pronounces it, and stripping too eagerly
/// mangles ordinary prose. The "leaves alone" tests are the ones that keep the
/// patterns honest.
final class SpeechTextSanitizerTests: XCTestCase {

    private let sanitizer = SpeechTextSanitizer()

    // MARK: - Markup is removed

    func test_boldAndItalicMarkersAreRemoved() {
        XCTAssertEqual(sanitizer.plainText(from: "You **already** decided."),
                       "You already decided.")
        XCTAssertEqual(sanitizer.plainText(from: "You *already* decided."),
                       "You already decided.")
        XCTAssertEqual(sanitizer.plainText(from: "You __already__ decided."),
                       "You already decided.")
    }

    func test_headingMarkersAreRemoved() {
        XCTAssertEqual(sanitizer.plainText(from: "## What you said"), "What you said")
    }

    func test_inlineCodeIsSpokenWithoutBackticks() {
        XCTAssertEqual(sanitizer.plainText(from: "Set `reminderHour` to 22."),
                       "Set reminderHour to 22.")
    }

    func test_linkKeepsTextAndDropsURL() {
        XCTAssertEqual(sanitizer.plainText(from: "See [the notes](https://example.com/x) later."),
                       "See the notes later.")
    }

    func test_bareURLIsDropped() {
        // Character-by-character URL reading is the worst thing a TTS engine does.
        XCTAssertEqual(sanitizer.plainText(from: "Read https://example.com/a/b now."),
                       "Read now.")
    }

    func test_horizontalRuleIsDropped() {
        XCTAssertEqual(sanitizer.plainText(from: "First.\n---\nSecond."), "First. Second.")
    }

    func test_blockquoteMarkerIsRemoved() {
        XCTAssertEqual(sanitizer.plainText(from: "> You wrote this in March."),
                       "You wrote this in March.")
    }

    // MARK: - Lists get sentence boundaries

    func test_listItemsBecomeSentences() {
        // Without terminal punctuation the tokenizer runs the whole list into
        // one sentence and the chunker has nowhere to split.
        let text = """
            - sleep was poor
            - lunch was skipped
            - you said yes anyway
            """
        XCTAssertEqual(sanitizer.plainText(from: text),
                       "sleep was poor. lunch was skipped. you said yes anyway.")
    }

    func test_listItemAlreadyPunctuatedIsNotDoublePunctuated() {
        XCTAssertEqual(sanitizer.plainText(from: "- You slept badly."), "You slept badly.")
    }

    func test_numberedListMarkersAreRemoved() {
        XCTAssertEqual(sanitizer.plainText(from: "1. Take the offer\n2. Stay put"),
                       "Take the offer. Stay put.")
    }

    // MARK: - Ordinary prose is left alone

    func test_arithmeticAsterisksSurvive() {
        // "2 * 3 * 4" looks exactly like italics to a careless pattern.
        XCTAssertEqual(sanitizer.plainText(from: "You worked 2 * 3 * 4 hours."),
                       "You worked 2 * 3 * 4 hours.")
    }

    func test_snakeCaseNamesSurvive() {
        XCTAssertEqual(sanitizer.plainText(from: "The file_name_here stayed put."),
                       "The file_name_here stayed put.")
    }

    func test_midSentenceHyphenSurvives() {
        XCTAssertEqual(sanitizer.plainText(from: "It was a well-considered choice."),
                       "It was a well-considered choice.")
    }

    func test_plainProseIsUnchanged() {
        let text = "You have been circling this for three weeks."
        XCTAssertEqual(sanitizer.plainText(from: text), text)
    }

    func test_emptyInputProducesEmptyOutput() {
        XCTAssertEqual(sanitizer.plainText(from: ""), "")
        XCTAssertEqual(sanitizer.plainText(from: "\n\n   \n"), "")
    }

    // MARK: - Realistic advice reply

    func test_fullAdviceReply() {
        let markdown = """
            ## What I notice

            You've raised this **three times** since March, and each time the
            sticking point was the *commute*, not the salary.

            - March 4: "the drive would kill me"
            - April 19: same again
            - Today: still the drive

            ---

            See [your entry](https://example.com/e/1) for the full note.
            """
        let spoken = sanitizer.plainText(from: markdown)

        for marker in ["**", "*", "##", "---", "http", "[", "]"] {
            XCTAssertFalse(spoken.contains(marker), "markup survived: \(marker)")
        }
        XCTAssertTrue(spoken.contains("three times"))
        XCTAssertTrue(spoken.contains("your entry"))
        XCTAssertTrue(spoken.contains("March 4:"))
    }
}
