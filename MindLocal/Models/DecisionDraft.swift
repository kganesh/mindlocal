import Foundation
import FoundationModels

/// Guided-generation target for on-device extraction (spec §10.1).
/// Every field the model can't find in the note must stay empty —
/// enforced by the extraction instructions, and by the post-rule in
/// ExtractionService (empty `statement` == "not a decision").
@Generable
struct DecisionDraft: Equatable {
    @Guide(description: "Short title for the decision, max 8 words. Empty if no decision was made.")
    var title: String

    @Guide(description: "The decision itself, phrased as 'I decided to ...'. Empty if the note contains no decision.")
    var statement: String

    @Guide(description: "Situation, constraints, and stakes as stated in the note. Empty if not mentioned.")
    var context: String

    @Guide(description: "Alternatives the person said they considered. Empty array if none were mentioned. Never invent options.")
    var options: [OptionDraft]

    @Guide(description: "The person's stated reasons for the choice. Empty if not mentioned.")
    var rationale: String

    @Guide(description: "One of: career, money, health, family, work, other.")
    var domain: String

    @Guide(description: "One of: low, medium, high. Judge from stated stakes; default medium.")
    var stakes: String
}

@Generable
struct OptionDraft: Equatable {
    @Guide(description: "The alternative considered, in the person's words.")
    var text: String

    @Guide(description: "Why it was rejected, only if stated. Empty otherwise.")
    var rejectedBecause: String
}

extension DecisionDraft {
    var isDecision: Bool {
        !statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Fields worth a follow-up question, in priority order (spec §10.2).
    var missingFields: [String] {
        var missing: [String] = []
        if rationale.isEmpty { missing.append("rationale") }
        if options.isEmpty { missing.append("options") }
        return missing
    }

    func toDecision(rawTranscript: String?, occurredAt: Date?) -> Decision {
        let stakesValue = Stakes(rawValue: stakes) ?? .medium
        let anchor = occurredAt ?? .now
        return Decision(
            title: title.isEmpty ? String(statement.prefix(48)) : title,
            statement: statement,
            context: context,
            options: options.map {
                OptionConsidered(
                    text: $0.text,
                    rejectedBecause: $0.rejectedBecause.isEmpty ? nil : $0.rejectedBecause
                )
            },
            rationale: rationale,
            domain: Domain(rawValue: domain) ?? .other,
            stakes: stakesValue,
            revisitAt: Decision.revisitDate(for: stakesValue, occurredAt: anchor),
            rawTranscript: rawTranscript,
            occurredAt: occurredAt
        )
    }
}
