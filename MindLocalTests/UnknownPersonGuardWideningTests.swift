import XCTest
@testable import MindLocal

/// The guard now fires on bare capitalised names, not only possessives. That
/// buys recall at the cost of precision, and a false positive here is worse
/// than a miss: it refuses a question the app could have answered. So most of
/// these tests are about what must NOT be refused.
final class UnknownPersonGuardWideningTests: XCTestCase {

    // MARK: - Detection

    func test_bareNameIsFound_theCaseThatMotivatedThis() {
        // NLTagger tags "Nora" here as OtherWord, which is exactly why the
        // tagger is not used to find names.
        XCTAssertEqual(UnknownPersonGuard.capitalisedNames(in: "Did the birthday for Nora happen last week?"),
                       ["Nora"])
    }

    func test_bareNameWithoutPossessiveIsFound() {
        XCTAssertEqual(UnknownPersonGuard.capitalisedNames(in: "When did I last see Nora?"), ["Nora"])
    }

    func test_hyphenatedNameIsFound() {
        XCTAssertEqual(UnknownPersonGuard.capitalisedNames(in: "How did the meeting with Anne-Marie go?"),
                       ["Anne-Marie"])
    }

    func test_candidateNamesMergesBothDetectorsWithoutDuplicates() {
        let names = UnknownPersonGuard.candidateNames(in: "Did Nora's meeting with Nora happen?")
        XCTAssertEqual(names, ["Nora"])
    }

    // MARK: - Must not become candidates

    func test_sentenceOpenersAreNotNames() {
        for query in ["Did I sleep well?", "When was the trip?", "What happened last week?",
                      "How is work going?", "Tell me about last month", "Should I take it?"] {
            XCTAssertTrue(UnknownPersonGuard.capitalisedNames(in: query).isEmpty,
                          "opener treated as a name in: \(query)")
        }
    }

    func test_placesAndOrganisationsAreExcluded() {
        // The whole reason NLTagger is still here.
        XCTAssertTrue(UnknownPersonGuard.capitalisedNames(in: "Did I go to Boston last week?").isEmpty)
        XCTAssertTrue(UnknownPersonGuard.capitalisedNames(in: "Was the trip to Paris in August?").isEmpty)
        XCTAssertTrue(UnknownPersonGuard.capitalisedNames(in: "Did Google reply about the offer?").isEmpty)
    }

    func test_monthsAndWeekdaysAreExcluded() {
        XCTAssertTrue(UnknownPersonGuard.capitalisedNames(in: "What did I do on Monday?").isEmpty)
        XCTAssertTrue(UnknownPersonGuard.capitalisedNames(in: "Was it in August?").isEmpty)
    }

    func test_lowercaseNamesAreNotDetected() {
        // Documented limitation, not an oversight: dropping the capitalisation
        // requirement makes every ordinary word a candidate.
        XCTAssertTrue(UnknownPersonGuard.capitalisedNames(in: "tell me about nora").isEmpty)
    }

    // MARK: - The graph gate

    func test_graphMentions_matchesWholeWordsOnly() {
        let graph = MemoryGraph(
            builtAt: .now,
            nodes: [MemoryNode(id: .init(rawValue: "e1"), kind: .entry,
                               title: "Anaheim trip planning")],
            edges: [],
            sourceFingerprint: "test")
        XCTAssertTrue(UnknownPersonGuard.graphMentions("Anaheim", in: graph))
        XCTAssertFalse(UnknownPersonGuard.graphMentions("Ana", in: graph),
                       "prefix match would refuse real questions about Ana")
    }

    func test_nameAppearingAnywhereInTheGraphIsNotRefused() {
        // A project, not a person. The app has entries about it, so refusing
        // would be wrong even though nobody is named Kokoro.
        let graph = MemoryGraph(
            builtAt: .now,
            nodes: [MemoryNode(id: .init(rawValue: "e1"), kind: .entry,
                               title: "Kokoro integration notes")],
            edges: [],
            sourceFingerprint: "test")
        XCTAssertNil(UnknownPersonGuard.refusal(for: "Did I finish the Kokoro work?",
                                                people: [], graph: graph))
    }

    func test_nameAppearingNowhereIsRefused() {
        let graph = MemoryGraph(
            builtAt: .now,
            nodes: [MemoryNode(id: .init(rawValue: "e1"), kind: .entry,
                               title: "Ordinary Tuesday")],
            edges: [],
            sourceFingerprint: "test")
        let refusal = UnknownPersonGuard.refusal(for: "Did the birthday for Nora happen last week?",
                                                 people: [], graph: graph)
        XCTAssertNotNil(refusal)
        XCTAssertTrue(refusal?.contains("Nora") == true)
    }

    func test_placeIsNotRefusedEvenWhenAbsentFromTheGraph() {
        // Boston survives on the tagger alone — it never becomes a candidate,
        // so the graph gate is never consulted.
        XCTAssertNil(UnknownPersonGuard.refusal(for: "Did I go to Boston last week?",
                                                people: [], graph: .empty))
    }
}
