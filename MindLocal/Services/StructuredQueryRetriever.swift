import Foundation

/// Applies a `QueryIntentDraft`'s extracted filters deterministically over the
/// in-memory Experience/Decision/Event collections. The model only identifies
/// WHAT is being asked for; matching, filtering, sorting, and limiting happen
/// here in plain code, so the result is guaranteed correct rather than guessed
/// from embedding similarity to the question text.
enum StructuredQueryRetriever {
    private static let defaultLimit = 5
    private static let maxLimit = 10

    private static func resolvedLimit(_ requested: Int) -> Int {
        requested > 0 ? min(requested, maxLimit) : defaultLimit
    }

    private static func matchesTopics(_ keywords: [String], in haystack: [String]) -> Bool {
        guard !keywords.isEmpty else { return true }
        let hay = haystack.filter { !$0.isEmpty }.joined(separator: " ").lowercased()
        return keywords.contains { hay.contains($0.lowercased()) }
    }

    @MainActor
    static func matchedExperiences(intent: QueryIntentDraft, among experiences: [Experience]) -> [Experience] {
        var results = experiences
        if !intent.tone.isEmpty, let tone = ExperienceTone(rawValue: intent.tone.lowercased()) {
            results = results.filter { $0.tone == tone }
        }
        if !intent.domain.isEmpty, let domain = Domain(rawValue: intent.domain.lowercased()) {
            results = results.filter { $0.domain == domain }
        }
        if !intent.topicKeywords.isEmpty {
            results = results.filter {
                // outcomes included so a missed/forgotten commitment ("missed
                // the team meeting") is findable by a later structured question
                // like "when did I miss meetings", not just buried prose.
                matchesTopics(intent.topicKeywords, in: [$0.title, $0.summary] + $0.tags + $0.activities + $0.outcomes)
            }
        }
        results.sort { intent.sortOrder == "oldest" ? $0.timelineDate < $1.timelineDate : $0.timelineDate > $1.timelineDate }
        return Array(results.prefix(resolvedLimit(intent.limit)))
    }

    @MainActor
    static func matchedDecisions(intent: QueryIntentDraft, among decisions: [Decision]) -> [Decision] {
        var results = decisions
        if !intent.domain.isEmpty, let domain = Domain(rawValue: intent.domain.lowercased()) {
            results = results.filter { $0.domain == domain }
        }
        if !intent.topicKeywords.isEmpty {
            results = results.filter {
                matchesTopics(intent.topicKeywords, in: [$0.title, $0.statement, $0.rationale])
            }
        }
        results.sort { intent.sortOrder == "oldest" ? $0.timelineDate < $1.timelineDate : $0.timelineDate > $1.timelineDate }
        return Array(results.prefix(resolvedLimit(intent.limit)))
    }

    @MainActor
    static func matchedEvents(intent: QueryIntentDraft, among events: [Event]) -> [Event] {
        var results = events
        if !intent.domain.isEmpty, let domain = Domain(rawValue: intent.domain.lowercased()) {
            results = results.filter { $0.domain == domain }
        }
        if !intent.topicKeywords.isEmpty {
            results = results.filter { matchesTopics(intent.topicKeywords, in: [$0.title, $0.notes]) }
        }
        results.sort { intent.sortOrder == "oldest" ? $0.date < $1.date : $0.date > $1.date }
        return Array(results.prefix(resolvedLimit(intent.limit)))
    }
}
