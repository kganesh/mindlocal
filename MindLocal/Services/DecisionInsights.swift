import Foundation

/// Deterministic aggregates over decisions that have a recorded outcome — the
/// factual base of the "you-model" (domain-model.md, Phase 2). No AI: just
/// counting, so it's trustworthy and testable. AI-synthesized convictions come
/// in Phase 3 and will build on these numbers.
enum DecisionInsights {

    /// A count of outcomes for one grouping (a domain, a value, or overall).
    struct Tally: Equatable {
        var workedOut = 0
        var mixed = 0
        var regret = 0
        var tooEarly = 0

        /// Conclusive outcomes (excludes "too early to tell").
        var decided: Int { workedOut + mixed + regret }
        var total: Int { decided + tooEarly }

        /// Share of conclusive outcomes that worked out (nil if none decided yet).
        var workedOutRate: Double? {
            decided > 0 ? Double(workedOut) / Double(decided) : nil
        }

        mutating func add(_ result: OutcomeResult) {
            switch result {
            case .workedOut: workedOut += 1
            case .mixed:     mixed += 1
            case .regret:    regret += 1
            case .tooEarly:  tooEarly += 1
            }
        }
    }

    /// A named group with its outcome tally (e.g. "Money", "family time").
    struct Group: Identifiable, Equatable {
        var name: String
        var tally: Tally
        var id: String { name }
    }

    /// Decisions that have a recorded outcome — the only ones that carry signal.
    private static func withOutcomes(_ decisions: [Decision]) -> [(Decision, OutcomeResult)] {
        decisions.compactMap { d in d.outcome.map { (d, $0.result) } }
    }

    static func overall(_ decisions: [Decision]) -> Tally {
        var tally = Tally()
        for (_, result) in withOutcomes(decisions) { tally.add(result) }
        return tally
    }

    /// Outcome tallies per domain, most decisions first.
    static func byDomain(_ decisions: [Decision]) -> [Group] {
        var groups: [String: Tally] = [:]
        for (d, result) in withOutcomes(decisions) {
            groups[d.domain.label, default: Tally()].add(result)
        }
        return groups
            .map { Group(name: $0.key, tally: $0.value) }
            .sorted { $0.tally.total != $1.tally.total ? $0.tally.total > $1.tally.total : $0.name < $1.name }
    }

    /// Outcome tallies per prioritized value, most decisions first. Values are
    /// grouped case-insensitively but shown in their first-seen form.
    static func byPrioritizedValue(_ decisions: [Decision]) -> [Group] {
        var tallies: [String: Tally] = [:]   // key: lowercased
        var display: [String: String] = [:]  // key: first-seen original
        for (d, result) in withOutcomes(decisions) {
            for raw in d.valuesPrioritized {
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }
                let key = value.lowercased()
                if display[key] == nil { display[key] = value }
                tallies[key, default: Tally()].add(result)
            }
        }
        return tallies
            .map { Group(name: display[$0.key] ?? $0.key, tally: $0.value) }
            .sorted { $0.tally.total != $1.tally.total ? $0.tally.total > $1.tally.total : $0.name < $1.name }
    }
}
