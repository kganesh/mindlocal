import Foundation
import FoundationModels

/// Guided-generation target for extracting an experience. Grounded in the note —
/// every field the model can't find stays empty; an empty `summary` means the
/// note describes no experience.
@Generable
struct ExperienceDraft: Equatable {
    @Guide(description: "Short title for the experience, max 8 words. Empty if the note describes no experience.")
    var title: String

    @Guide(description: "What happened, in a sentence or two, in the person's words. Empty if the note describes no experience.")
    var summary: String

    @Guide(description: "The emotions the person expressed about it. Empty if none stated.")
    var feelings: String

    @Guide(description: "Overall tone of the experience. One of: pleasant, unpleasant, mixed.")
    var tone: String

    @Guide(description: "What made it pleasant or unpleasant — the factors the person mentioned. Empty if not stated.")
    var factors: String

    @Guide(description: "What the person did or how they responded. Empty if not mentioned.")
    var response: String

    @Guide(description: "The takeaway the person stated or clearly implied — what they'd do again (if pleasant) or differently (if unpleasant). Empty if not stated.")
    var learning: String

    @Guide(description: "One to three short theme tags. Empty array if unclear. Never invent.")
    var tags: [String]

    @Guide(description: "One of: career, money, health, family, work, other.")
    var domain: String

    @Guide(description: "Specific individuals involved, by name or a specific relationship (e.g. 'Sam', 'my manager', 'Mom'). Do NOT include groups or plurals ('the team', 'senior engineers', 'colleagues'), generic job titles, or the writer themselves ('me', 'self'). Empty if none. Never invent.")
    var people: [String]

    @Guide(description: "Concrete activities or actions the person did, each a short phrase (e.g. 'morning run', 'finished the report'). Empty if none. Never invent.")
    var activities: [String]

    @Guide(description: "Results or outcomes — how things turned out. Each a short phrase. Empty if none stated.")
    var outcomes: [String]

    @Guide(description: "Forward-looking wants, wishes, or hopes the person expressed (e.g. 'wants to travel more', 'hopes the interview goes well'). Empty if none. Never invent.")
    var hopes: [String]

    @Guide(description: "Any decisions the person mentions having made in this note, as structured records. Empty array if they did not mention deciding anything. Never invent a decision.")
    var decisions: [DecisionDraft]
}

extension ExperienceDraft {
    var isExperience: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toExperience(rawText: String?, occurredAt: Date?) -> Experience {
        Experience(
            title: title.isEmpty ? String(summary.prefix(48)) : title,
            summary: summary,
            feelings: feelings,
            tone: ExperienceTone(rawValue: tone.lowercased()) ?? .mixed,
            factors: factors,
            response: response,
            learning: learning,
            tags: tags.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            domain: Domain(rawValue: domain) ?? .other,
            rawText: rawText,
            occurredAt: occurredAt,
            people: ExperienceDraft.cleaned(people),
            activities: ExperienceDraft.cleaned(activities),
            outcomes: ExperienceDraft.cleaned(outcomes),
            hopes: ExperienceDraft.cleaned(hopes)
        )
    }

    static func cleaned(_ items: [String]) -> [String] {
        items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
