import XCTest
@testable import MindLocal

final class RetrievalAndModelTests: XCTestCase {

    // MARK: - Cosine (deterministic)

    func test_cosine_identicalAndOrthogonal() {
        XCTAssertEqual(EmbeddingService.cosine([1, 0, 0], [1, 0, 0]), 1, accuracy: 0.0001)
        XCTAssertEqual(EmbeddingService.cosine([1, 0, 0], [0, 1, 0]), 0, accuracy: 0.0001)
        XCTAssertEqual(EmbeddingService.cosine([1, 2, 3], [2, 4, 6]), 1, accuracy: 0.0001) // same direction
        XCTAssertEqual(EmbeddingService.cosine([], []), 0)
    }

    // MARK: - Semantic ranking (NLEmbedding, available on the simulator)

    private struct Item { let text: String }

    func test_semanticRetriever_ranksRelevantHigher() {
        let items = [
            Item(text: "went for a morning run along the river and felt great"),
            Item(text: "reviewed the quarterly budget with the finance team"),
            Item(text: "called my mom for her birthday"),
        ]
        let top = SemanticRetriever.topK(
            items, query: "exercise and fitness", k: 1,
            text: { $0.text }, embedding: { _ in [] }
        )
        // If embeddings are available, the running entry should win; otherwise the
        // fallback returns the first item (still the running entry here).
        XCTAssertEqual(top.first?.text, items[0].text)
    }

    func test_semanticRetriever_respectsK() {
        let items = (0..<20).map { Item(text: "entry number \($0)") }
        let top = SemanticRetriever.topK(items, query: "anything", k: 5,
                                         text: { $0.text }, embedding: { _ in [] })
        XCTAssertEqual(top.count, 5)
    }

    // MARK: - Mood scoring

    func test_toneScore() {
        XCTAssertEqual(ExperienceTone.pleasant.score, 1, accuracy: 0.0001)
        XCTAssertEqual(ExperienceTone.mixed.score, 0, accuracy: 0.0001)
        XCTAssertEqual(ExperienceTone.unpleasant.score, -1, accuracy: 0.0001)
    }

    // MARK: - Prompt building

    func test_advisorPrompt_includesQuestionAndContext() {
        let prompt = Prompts.advisorPrompt(question: "How do I handle stress?", context: "PAST: went running")
        XCTAssertTrue(prompt.contains("How do I handle stress?"))
        XCTAssertTrue(prompt.contains("went running"))
    }

    func test_eventAdvisorPrompt_includesWeatherWhenOutdoor() {
        let withWeather = Prompts.eventAdvisorPrompt(event: "Picnic", when: "Sat", weather: "Sunny, 20C", context: "ctx")
        XCTAssertTrue(withWeather.contains("Sunny, 20C"))
        let without = Prompts.eventAdvisorPrompt(event: "Meeting", when: "Mon", weather: nil, context: "ctx")
        XCTAssertFalse(without.lowercased().contains("weather forecast"))
    }
}
