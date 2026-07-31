import Foundation
import FoundationModels

/// A compact, Sendable snapshot of a saved decision — decouples the advisor from
/// SwiftData's (MainActor-bound, non-Sendable) `Decision`.
struct DecisionSummary: Sendable, Identifiable {
    let id: UUID
    let createdAt: Date
    let title: String
    let statement: String
    let rationale: String
    let domain: String
    let stakes: String
    let outcome: String?
}

/// A compact, Sendable snapshot of a saved experience for advisor context.
struct ExperienceSummary: Sendable, Identifiable {
    let id: UUID
    let createdAt: Date
    let title: String
    let summary: String
    let feelings: String
    let tone: String
    let factors: String
    let learning: String
    let domain: String
    let tags: [String]
    let outcomes: [String]
}

/// A compact, Sendable snapshot of a saved reminder for advisor context.
struct ReminderSummary: Sendable, Identifiable {
    let id: UUID
    let createdAt: Date
    let text: String
    let personName: String
    let isDone: Bool
}

/// A compact, Sendable snapshot of a saved event for advisor context.
struct EventSummary: Sendable, Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let notes: String
    let personName: String
    let domain: String
}

/// A pre-rendered profile (aliases + relationship edges) for a person named in
/// the question — ground truth from the People graph, not text similarity.
struct PersonProfileSummary: Sendable, Identifiable {
    let id: UUID
    let text: String
}

protocol AdvisingServicing: Sendable {
    /// Answers `question`, grounded in the user's past decisions, experiences,
    /// reminders, events, and — for any person named in the question — their
    /// actual People-graph profile.
    func advise(question: String,
                decisions: [DecisionSummary],
                experiences: [ExperienceSummary],
                reminders: [ReminderSummary],
                events: [EventSummary],
                people: [PersonProfileSummary],
                graphContext: String) async throws -> String

    /// Proactive preparation advice for an upcoming event, grounded in the
    /// (already-filtered, relevant) decisions and experiences, optionally
    /// factoring in a weather forecast for outdoor events.
    func eventAdvice(event: String,
                     when: Date,
                     weather: String?,
                     decisions: [DecisionSummary],
                     experiences: [ExperienceSummary]) async throws -> String

    /// Reads the STRUCTURE of a question (a tone/topic/count/sort it implies),
    /// not an answer — used to drive a deterministic retrieval pass alongside
    /// semantic search. Never throws to the caller in practice; extraction
    /// failure just means no structured match is attempted.
    func extractIntent(from question: String) async throws -> QueryIntentDraft
}

enum AdviceError: Error {
    case modelUnavailable
    case noQuestion
}

/// On-device advisor (spec §10.3) via Foundation Models, grounded in past
/// decisions/experiences retrieved by semantic similarity (`SemanticRetriever`,
/// via `Decision.embedding`/`Experience.embedding`) plus, when a question implies
/// a structured filter, a deterministic pass (`StructuredQueryRetriever`).
final class AdviceService: AdvisingServicing {
    /// Same permissive-guardrails rationale as extraction elsewhere — this only
    /// reads the user's own question, so shouldn't refuse on ordinary topics.
    private static let intentModel = SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    )

    /// The default model's guardrails false-positive on the exact thing this
    /// app is for: answering questions grounded in the user's own journaled
    /// decisions/experiences, which routinely name real people the user knows
    /// (e.g. "Who is Akhil") — the default filter treats that as a request for
    /// info about a named individual and refuses outright.
    private static let answerModel = SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    )

    func extractIntent(from question: String) async throws -> QueryIntentDraft {
        guard Self.intentModel.isAvailable else { throw AdviceError.modelUnavailable }
        let session = LanguageModelSession(
            model: Self.intentModel,
            instructions: Prompts.queryIntentInstructions
        )
        let response = try await session.respond(
            to: Prompts.queryIntentPrompt(question: question),
            generating: QueryIntentDraft.self
        )
        return response.content
    }

    func advise(question: String,
                decisions: [DecisionSummary],
                experiences: [ExperienceSummary],
                reminders: [ReminderSummary],
                events: [EventSummary],
                people: [PersonProfileSummary],
                graphContext: String = "") async throws -> String {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw AdviceError.noQuestion }
        guard Self.answerModel.isAvailable else { throw AdviceError.modelUnavailable }

        let session = LanguageModelSession(
            model: Self.answerModel,
            instructions: Prompts.advisorInstructions
        )
        let response = try await session.respond(
            to: Prompts.advisorPrompt(
                question: q,
                context: Self.context(
                    decisions: decisions, experiences: experiences,
                    reminders: reminders, events: events, people: people,
                    graphContext: graphContext
                )
            )
        )
        return response.content
    }

    func eventAdvice(event: String,
                     when: Date,
                     weather: String?,
                     decisions: [DecisionSummary],
                     experiences: [ExperienceSummary]) async throws -> String {
        guard Self.answerModel.isAvailable else { throw AdviceError.modelUnavailable }

        let session = LanguageModelSession(
            model: Self.answerModel,
            instructions: Prompts.eventAdvisorInstructions
        )
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let response = try await session.respond(
            to: Prompts.eventAdvisorPrompt(
                event: event,
                when: formatter.string(from: when),
                weather: weather,
                context: Self.context(decisions: decisions, experiences: experiences)
            )
        )
        return response.content
    }

    /// Formats the most relevant decisions, experiences, reminders, and events
    /// into a compact context. `reminders`/`events`/`people` default empty for
    /// callers (like event-prep advice) that don't retrieve them.
    static func context(
        decisions: [DecisionSummary],
        experiences: [ExperienceSummary],
        reminders: [ReminderSummary] = [],
        events: [EventSummary] = [],
        people: [PersonProfileSummary] = [],
        graphContext: String = ""
    ) -> String {
        let formatter = DateFormatter()
        // Day-level, not month-level — a question like "when did I last meet
        // X" needs the actual date, and truncating to "yyyy-MM" made that
        // physically impossible to answer precisely regardless of how the
        // model reasoned over the rest of the context.
        formatter.dateFormat = "yyyy-MM-dd"
        var blocks: [String] = []

        // People go first — this is ground truth from the graph, not text
        // similarity, so it should anchor the model before looser retrieved
        // text that merely happens to mention similar words.
        if !people.isEmpty {
            blocks.append("PEOPLE (authoritative — use this, not inference from other entries, for who someone is or how they're related):\n"
                + people.map(\.text).joined(separator: "\n\n"))
        }

        if !graphContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append("MEMORY GRAPH CONTEXT (retrieved from linked entries, people, events, reminders, decisions, and relationships):\n"
                + graphContext)
        }

        if !decisions.isEmpty {
            let recent = decisions.sorted { $0.createdAt > $1.createdAt }.prefix(12)
            let lines = recent.enumerated().map { index, d -> String in
                var parts = ["\(index + 1). [\(d.domain), \(d.stakes) stakes, \(formatter.string(from: d.createdAt))] \(d.title)"]
                if !d.statement.isEmpty { parts.append("   Decided: \(clip(d.statement))") }
                if !d.rationale.isEmpty { parts.append("   Because: \(clip(d.rationale))") }
                if let o = d.outcome, !o.isEmpty { parts.append("   Outcome: \(clip(o))") }
                return parts.joined(separator: "\n")
            }
            blocks.append("PAST DECISIONS:\n" + lines.joined(separator: "\n\n"))
        }

        if !experiences.isEmpty {
            let recent = experiences.sorted { $0.createdAt > $1.createdAt }.prefix(12)
            let lines = recent.enumerated().map { index, e -> String in
                var parts = ["\(index + 1). [\(e.tone), \(e.domain), \(formatter.string(from: e.createdAt))] \(e.title)"]
                if !e.summary.isEmpty { parts.append("   Happened: \(clip(e.summary))") }
                if !e.outcomes.isEmpty { parts.append("   Outcomes: \(clip(e.outcomes.joined(separator: "; ")))") }
                if !e.factors.isEmpty { parts.append("   Because: \(clip(e.factors))") }
                if !e.learning.isEmpty { parts.append("   Takeaway: \(clip(e.learning))") }
                return parts.joined(separator: "\n")
            }
            blocks.append("PAST EXPERIENCES (pleasant to recreate, unpleasant to handle better):\n" + lines.joined(separator: "\n\n"))
        }

        if !reminders.isEmpty {
            let recent = reminders.sorted { $0.createdAt > $1.createdAt }.prefix(12)
            let lines = recent.enumerated().map { index, r -> String in
                var line = "\(index + 1). [\(r.isDone ? "done" : "open")] \(clip(r.text))"
                if !r.personName.isEmpty { line += " (with \(r.personName))" }
                return line
            }
            blocks.append("REMINDERS (things noted to ask/bring up with someone):\n" + lines.joined(separator: "\n"))
        }

        if !events.isEmpty {
            let recent = events.sorted { $0.date > $1.date }.prefix(12)
            let lines = recent.enumerated().map { index, e -> String in
                var line = "\(index + 1). [\(e.domain), \(formatter.string(from: e.date))] \(e.title)"
                if !e.personName.isEmpty { line += " (with \(e.personName))" }
                if !e.notes.isEmpty { line += " — \(clip(e.notes, max: 120))" }
                return line
            }
            blocks.append("EVENTS (scheduled or past):\n" + lines.joined(separator: "\n"))
        }

        return fitToBudget(blocks)
    }

    /// The blocks above are built independently, each already capped to at most
    /// 12 items — but 12 decisions + 12 experiences + reminders + events + a full
    /// People profile + graph context routinely add up to several thousand
    /// characters once a journal has any real history (18 decisions/32
    /// experiences was enough to push a single request past the on-device
    /// model's 4096-token window with zero room left to generate a response —
    /// a hard failure, not a quality tradeoff). Assemble blocks in priority
    /// order (People and the graph context are ground truth and usually small;
    /// Decisions/Experiences are the bulky, lower-precision fallback) and keep
    /// only what fits a conservative character budget, so a heavy journal
    /// degrades to its most relevant context instead of throwing.
    private static let contextCharacterBudget = 6_000

    private static func fitToBudget(_ blocks: [String]) -> String {
        guard !blocks.isEmpty else { return "(no past decisions or experiences on record)" }
        var kept: [String] = []
        var used = 0
        for block in blocks {
            let cost = block.count + 2   // "\n\n" separator
            guard used + cost <= contextCharacterBudget else { continue }
            kept.append(block)
            used += cost
        }
        // Every block already fits the budget individually via its own 12-item
        // cap, so an empty `kept` here would mean even the smallest (People)
        // block alone exceeded it — fall back to it truncated rather than
        // sending nothing.
        if kept.isEmpty, let first = blocks.first {
            return String(first.prefix(contextCharacterBudget))
        }
        return kept.joined(separator: "\n\n")
    }

    private static func clip(_ text: String, max: Int = 240) -> String {
        text.count <= max ? text : String(text.prefix(max)) + "…"
    }
}

/// Deterministic mock for previews and tests.
final class MockAdviceService: AdvisingServicing {
    func advise(question: String,
                decisions: [DecisionSummary],
                experiences: [ExperienceSummary],
                reminders: [ReminderSummary],
                events: [EventSummary],
                people: [PersonProfileSummary],
                graphContext: String = "") async throws -> String {
        if decisions.isEmpty && experiences.isEmpty && reminders.isEmpty && events.isEmpty && people.isEmpty
            && graphContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "You don't have any saved decisions or experiences yet, so I can only offer general guidance."
        }
        return "Drawing on your history — the choices you've made and what you've lived through — I'd lean this way."
    }

    func extractIntent(from question: String) async throws -> QueryIntentDraft {
        QueryIntentDraft(tone: "", domain: "", topicKeywords: [], sortOrder: "recent", limit: 0)
    }

    func eventAdvice(event: String,
                     when: Date,
                     weather: String?,
                     decisions: [DecisionSummary],
                     experiences: [ExperienceSummary]) async throws -> String {
        "Before \(event): last time something similar came up it went reasonably well — repeat what worked, and jot down two questions to ask."
    }
}

extension ExperienceSummary {
    @MainActor
    init(_ experience: Experience) {
        self.init(
            id: experience.id,
            // timelineDate (occurredAt, falling back to createdAt) is when the
            // moment actually happened — createdAt alone is only when it was
            // typed into the app, which is wrong for "when did X happen"
            // questions whenever an entry is backfilled or logged a day late.
            createdAt: experience.timelineDate,
            title: experience.title,
            summary: experience.summary,
            feelings: experience.feelings,
            tone: experience.tone.label,
            factors: experience.factors,
            learning: experience.learning,
            domain: experience.domain.label,
            tags: experience.tags,
            outcomes: experience.outcomes
        )
    }
}

extension DecisionSummary {
    @MainActor
    init(_ decision: Decision) {
        self.init(
            id: decision.id,
            // Same rationale as ExperienceSummary — the decision's actual
            // timelineDate, not the record's raw createdAt.
            createdAt: decision.timelineDate,
            title: decision.title,
            statement: decision.statement,
            rationale: decision.rationale,
            domain: decision.domain.label,
            stakes: decision.stakes.label,
            outcome: decision.outcome.map { outcome in
                outcome.notes.isEmpty ? outcome.result.label : "\(outcome.result.label) — \(outcome.notes)"
            }
        )
    }
}

extension ReminderSummary {
    @MainActor
    init(_ reminder: Reminder) {
        self.init(
            id: reminder.id,
            createdAt: reminder.createdAt,
            text: reminder.text,
            personName: reminder.person?.name ?? reminder.personName,
            isDone: reminder.isDone
        )
    }
}

extension EventSummary {
    @MainActor
    init(_ event: Event) {
        self.init(
            id: event.id,
            date: event.date,
            title: event.title,
            notes: event.notes,
            personName: event.person?.name ?? "",
            domain: event.domain.label
        )
    }
}
