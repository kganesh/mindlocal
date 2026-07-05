import Foundation

/// Picks the decisions and experiences most relevant to an event, by domain and
/// keyword/tag overlap. Pure and testable. Empty results mean "nothing logged is
/// relevant yet" — the caller should prompt the user rather than invent advice.
enum EventMatcher {
    private static let stopWords: Set<String> = [
        "meeting", "event", "with", "about", "this", "that", "have", "will",
        "from", "your", "some", "being", "into", "over", "after", "before"
    ]

    static func keywords(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !stopWords.contains($0) })
    }

    static func relevant(
        eventDomain: String,
        keywords: Set<String>,
        decisions: [DecisionSummary],
        experiences: [ExperienceSummary],
        limit: Int = 6
    ) -> (decisions: [DecisionSummary], experiences: [ExperienceSummary]) {
        let domain = eventDomain.lowercased()

        func score(domainMatch: Bool, haystack: String) -> Int {
            var s = domainMatch ? 2 : 0
            let hay = haystack.lowercased()
            for keyword in keywords where hay.contains(keyword) { s += 1 }
            return s
        }

        var decisionScores: [(item: DecisionSummary, score: Int)] = []
        for decision in decisions {
            let haystack = "\(decision.title) \(decision.statement) \(decision.rationale)"
            let s = score(domainMatch: decision.domain.lowercased() == domain, haystack: haystack)
            if s > 0 { decisionScores.append((decision, s)) }
        }
        decisionScores.sort { first, second in
            if first.score != second.score { return first.score > second.score }
            return first.item.createdAt > second.item.createdAt
        }
        let topDecisions = decisionScores.prefix(limit).map { $0.item }

        var experienceScores: [(item: ExperienceSummary, score: Int)] = []
        for experience in experiences {
            let haystack = "\(experience.title) \(experience.summary) \(experience.factors) \(experience.learning) \(experience.tags.joined(separator: " "))"
            let s = score(domainMatch: experience.domain.lowercased() == domain, haystack: haystack)
            if s > 0 { experienceScores.append((experience, s)) }
        }
        experienceScores.sort { first, second in
            if first.score != second.score { return first.score > second.score }
            return first.item.createdAt > second.item.createdAt
        }
        let topExperiences = experienceScores.prefix(limit).map { $0.item }

        return (Array(topDecisions), Array(topExperiences))
    }
}
