import Foundation
import FoundationModels
import SwiftData

/// Guided-generation target for extracting an experience. Grounded in the note —
/// every field the model can't find stays empty; an empty `summary` means the
/// note describes no experience.
@Generable
struct ExperienceDraft: Equatable {
    @Guide(description: "Short title for the experience, max 8 words.")
    var title: String

    @Guide(description: "What actually happened, in a sentence or two. Keep any stated time of day (e.g. '4 o'clock', 'in the afternoon') — it is part of what happened.")
    var summary: String

    @Guide(description: "The emotions the person expressed about it.")
    var feelings: String

    // .anyOf hard-constrains the value, for the same reason it does on
    // QueryIntentDraft.questionType. A description alone let the model answer
    // with words it preferred — "positive", "good", "productive" — none of
    // which are raw values, so `ExperienceTone(rawValue:) ?? .mixed` below
    // silently turned an unmistakably good day into Mixed. A wrong tone is
    // invisible: it looks like a judgement call rather than a parse failure,
    // and it feeds the mood trend chart.
    @Guide(description: "Overall tone the writer conveys. Use mixed ONLY when they describe both good and bad parts — a day they call good or productive throughout is pleasant, not mixed.",
           .anyOf(["pleasant", "unpleasant", "mixed"]))
    var tone: String

    @Guide(description: "What made it pleasant or unpleasant.")
    var factors: String

    @Guide(description: "What the person did or how they responded.")
    var response: String

    @Guide(description: "The takeaway they stated or clearly implied — what they'd do again, or differently.")
    var learning: String

    @Guide(description: "One to three short theme tags.")
    var tags: [String]

    @Guide(description: "Which area of life this belongs to.",
           .anyOf(["career", "money", "health", "family", "work", "other"]))
    var domain: String

    @Guide(description: "Specific individuals involved, by name or specific relationship (e.g. 'Sam', 'my manager', 'Mom'). Not groups ('the team', 'colleagues'), generic job titles, or the writer themselves.")
    var people: [String]

    @Guide(description: "Concrete actions the person did, each a short phrase (e.g. 'morning run', 'finished the report'). Arguments and disagreements belong in conflicts, never here.")
    var activities: [String]

    @Guide(description: "How things actually turned out, including a missed, failed, or forgotten commitment (e.g. 'forgot the dentist appointment'). Each a short phrase. Conflicts belong in conflicts.")
    var outcomes: [String]

    @Guide(description: "Forward-looking wants, wishes, or hopes (e.g. 'hopes the interview goes well').")
    var hopes: [String]

    @Guide(description: "Interpersonal conflicts, arguments, disagreements, or tension with a specific person. An unpleasant event with no interpersonal disagreement is NOT a conflict.")
    var conflicts: [ConflictDraft]

    @Guide(description: "Action items to remember for a future interaction with a specific person (e.g. 'ask my doctor about the referral'). Also add one when the writer mentions missing or failing to connect with a named person. A general wish with no specific person belongs in hopes.")
    var reminders: [ReminderDraft]

    @Guide(description: "Upcoming appointments, meetings, or scheduled visits WITH a stated date/time. With no specific date/time it belongs in reminders or hopes instead.")
    var appointments: [AppointmentDraft]

    @Guide(description: "Decisions the person mentions having made in this note.")
    var decisions: [DecisionDraft]

    @Guide(description: "Activities that ALREADY happened with a specific named person (e.g. 'met David for coffee') — a candidate calendar Event. Not activities done alone or with an unnamed group.")
    var activityEvents: [ActivityEventDraft]

    @Guide(description: "A named person's occupation, only where the note explicitly states it (e.g. 'David, a nurse'). A role reference like 'my manager' is a relationship, not a job title.")
    var personOccupations: [PersonOccupationDraft]

    @Guide(description: "A named person's stated ongoing like or dislike (e.g. 'Akhil loves chocolate cake'). Not a one-off reaction ('was excited about the ice cream today').")
    var personPreferences: [PersonPreferenceDraft]
}

extension ExperienceDraft {
    var isExperience: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toExperience(rawText: String?, occurredAt: Date?) -> Experience {
        let experience = Experience(
            title: title.isEmpty ? String(summary.prefix(48)) : title,
            summary: summary,
            feelings: feelings,
            tone: ExperienceTone(rawValue: tone.lowercased()) ?? .mixed,
            factors: factors,
            response: response,
            learning: learning,
            tags: tags.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            domain: Domain(rawValue: domain.lowercased()) ?? .other,
            rawText: rawText,
            occurredAt: occurredAt,
            people: ExperienceDraft.cleaned(people),
            activities: ExperienceDraft.cleaned(activities),
            outcomes: ExperienceDraft.cleaned(outcomes),
            hopes: ExperienceDraft.cleaned(hopes)
        )
        // Conflicts and reminders carry no transcript/date dependency, so build them
        // here; each one's person link is set at save time by PersonResolver.linkPeople.
        experience.conflicts = conflicts.filter { $0.isConflict }.map { $0.toConflict() }
        experience.reminders = reminders.filter { $0.isReminder }.map { $0.toReminder() }
        return experience
    }

    static func cleaned(_ items: [String]) -> [String] {
        items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Overwrites an existing experience's AI-extracted fields with a fresh draft —
    /// used to re-run extraction after the user edits the original note to fix a
    /// typo. Replaces (not merges) conflicts, reminders, and decisions, deleting the
    /// old ones from `context` so they don't linger as orphaned rows. `id`,
    /// `createdAt`, `occurredAt`, `rawText`, `location`, and `linkedPeople` are left
    /// untouched — the caller re-links people afterward since `people` may differ.
    @MainActor
    func apply(to experience: Experience, in context: ModelContext) {
        experience.title = title.isEmpty ? String(summary.prefix(48)) : title
        experience.summary = summary
        experience.feelings = feelings
        experience.tone = ExperienceTone(rawValue: tone.lowercased()) ?? .mixed
        experience.factors = factors
        experience.response = response
        experience.learning = learning
        experience.tags = tags.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        experience.domain = Domain(rawValue: domain.lowercased()) ?? .other
        experience.people = ExperienceDraft.cleaned(people)
        experience.activities = ExperienceDraft.cleaned(activities)
        experience.outcomes = ExperienceDraft.cleaned(outcomes)
        experience.hopes = ExperienceDraft.cleaned(hopes)

        for old in experience.conflicts { context.delete(old) }
        for old in experience.reminders { context.delete(old) }
        for old in experience.decisions { context.delete(old) }
        experience.conflicts = conflicts.filter { $0.isConflict }.map { $0.toConflict() }
        experience.reminders = reminders.filter { $0.isReminder }.map { $0.toReminder() }
        experience.decisions = decisions.filter { $0.isDecision }
            .map { $0.toDecision(rawTranscript: experience.rawText, occurredAt: experience.occurredAt) }
    }
}
