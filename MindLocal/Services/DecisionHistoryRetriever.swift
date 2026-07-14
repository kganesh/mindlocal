import Foundation

/// Finds the past decisions most relevant to one you're making now — same domain,
/// shared/opposed values — and only ones you've recorded an outcome for, so it can
/// show how they turned out. Deterministic (domain-model.md, Phase 3: "your history
/// on this"). Grounds in-the-moment augmentation at decision capture.
enum DecisionHistoryRetriever {

    struct Match: Identifiable {
        let decision: Decision
        let score: Double
        var id: UUID { decision.id }
    }

    struct Result {
        var matches: [Match]
        /// A one-line pattern, e.g. "Your money decisions that traded off safety
        /// worked out 1 of 3." nil when there isn't enough signal.
        var pattern: String?

        var isEmpty: Bool { matches.isEmpty }
    }

    private static func norm(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    static func history(
        domain: Domain,
        prioritized: [String],
        tradedOff: [String],
        among decisions: [Decision],
        excluding id: UUID? = nil,
        limit: Int = 3
    ) -> Result {
        let prio   = Set(prioritized.map(norm)).subtracting([""])
        let traded = Set(tradedOff.map(norm)).subtracting([""])

        // Only decisions with a recorded outcome carry a "how it went" signal.
        let candidates = decisions.filter { $0.id != id && $0.outcome != nil }

        func score(_ d: Decision) -> Double {
            let dPrio   = Set(d.valuesPrioritized.map(norm))
            let dTraded = Set(d.valuesTradedOff.map(norm))
            let domainScore: Double = d.domain == domain ? 2.0 : 0.0
            let prioHit   = prio.intersection(dPrio).count
            let tradedHit = traded.intersection(dTraded).count
            // Same value on opposite sides is a live tension worth surfacing.
            let crossA    = prio.intersection(dTraded).count
            let crossB    = traded.intersection(dPrio).count
            let valueScore = Double(prioHit + tradedHit) * 1.5 + Double(crossA + crossB)
            return domainScore + valueScore
        }

        var scored: [Match] = candidates.map { Match(decision: $0, score: score($0)) }
        scored = scored.filter { $0.score > 0 }
        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.decision.timelineDate > b.decision.timelineDate
        }

        let matches = Array(scored.prefix(limit))
        let pattern = matches.isEmpty ? nil : patternLine(domain: domain, traded: traded, candidates: candidates)
        return Result(matches: matches, pattern: pattern)
    }

    /// Prefer a value-scoped pattern ("traded off safety") when one is shared;
    /// otherwise fall back to the domain. Needs at least 2 decided outcomes.
    @MainActor
    private static func patternLine(domain: Domain, traded: Set<String>, candidates: [Decision]) -> String? {
        // Value-scoped: the shared traded-off value that appears most in history.
        if let value = traded.first(where: { v in
            candidates.contains { $0.valuesTradedOff.map(norm).contains(v) }
        }) {
            let slice = candidates.filter { $0.valuesTradedOff.map(norm).contains(value) }
            if let line = tallyLine(slice, subject: "decisions that traded off \(value)") { return line }
        }
        // Domain-scoped fallback.
        let slice = candidates.filter { $0.domain == domain }
        return tallyLine(slice, subject: "\(domain.label.lowercased()) decisions")
    }

    @MainActor
    private static func tallyLine(_ slice: [Decision], subject: String) -> String? {
        var worked = 0, decided = 0
        for d in slice {
            guard let r = d.outcome?.result else { continue }
            switch r {
            case .workedOut: worked += 1; decided += 1
            case .mixed, .regret: decided += 1
            case .tooEarly: break
            }
        }
        guard decided >= 2 else { return nil }
        return "Your \(subject) worked out \(worked) of \(decided)."
    }
}
