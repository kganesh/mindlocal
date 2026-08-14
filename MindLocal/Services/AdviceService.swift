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

    /// Same as `advise`, but returns a structured answer plus a report on
    /// whether its citations actually appear in the context it was given.
    /// Defaulted so existing conformances (test doubles) keep compiling; the
    /// default is deliberately ungrounded — only the real service can produce a
    /// meaningful report.
    func adviseGrounded(question: String,
                        decisions: [DecisionSummary],
                        experiences: [ExperienceSummary],
                        reminders: [ReminderSummary],
                        events: [EventSummary],
                        people: [PersonProfileSummary],
                        packedContext: MemoryGraphContextPacker.PackedContext)
    async throws -> (answer: GroundedAnswer, report: GroundingReport)

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

    /// Answers a question identified (by `QueryIntentDraft.questionType`) as
    /// asking who someone is or how they're related. When `people` names
    /// someone actually resolved from the People graph, answers grounded
    /// solely in their profile — no decisions/experiences/graph-context noise
    /// for the model to blend in. When `people` is empty (no known person
    /// matched), answers deterministically with no model call at all, rather
    /// than risk the model inventing a relationship for a name it's never
    /// seen.
    func answerWhoIs(question: String, people: [PersonProfileSummary]) async throws -> String
}

extension AdvisingServicing {
    func adviseGrounded(question: String,
                        decisions: [DecisionSummary],
                        experiences: [ExperienceSummary],
                        reminders: [ReminderSummary],
                        events: [EventSummary],
                        people: [PersonProfileSummary],
                        packedContext: MemoryGraphContextPacker.PackedContext)
    async throws -> (answer: GroundedAnswer, report: GroundingReport) {
        let text = try await advise(
            question: question, decisions: decisions, experiences: experiences,
            reminders: reminders, events: events, people: people,
            graphContext: packedContext.text
        )
        let answer = GroundedAnswer(
            answer: text, citedEvidence: [], citedPeople: [],
            citedDates: [], usedGeneralKnowledge: true
        )
        return (answer, GroundingReport())
    }
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

    /// Pure greedy decoding (always the single highest-probability token) was
    /// adopted to fix inconsistent answers across repeated identical
    /// questions — but a real "priorities for Akhil's birthday" answer then
    /// degenerated into a nonsensical, self-extending relationship chain
    /// ("...so you are his doctor's patient's doctor's patient's doctor...")
    /// that only stopped because it hit maximumResponseTokens. That's the
    /// classic failure mode of greedy decoding: with zero token-level
    /// entropy, a model has no way to escape a locally-repeating pattern once
    /// it starts one. `.random(top:seed:)` with a small top and a FIXED seed
    /// keeps the original goal (same question + same context → same answer,
    /// since a seeded RNG's draws are reproducible) while giving just enough
    /// escape room to break out of a repetition trap that greedy can't.
    private static let answerSampling = GenerationOptions.SamplingMode.random(top: 3, seed: 7)

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
            ),
            // maximumResponseTokens is set explicitly rather than left as a
            // framework default — an identical question overflowed the
            // context window right after switching away from default
            // sampling, with no change to context size, suggesting the
            // default output reservation isn't fixed across sampling modes.
            // Instructions already say "a few sentences"; 400 tokens is
            // generous room for that while keeping the INPUT budget
            // (4096 - this) known and constant instead of an opaque,
            // possibly-varying default.
            options: GenerationOptions(sampling: Self.answerSampling, maximumResponseTokens: 400)
        )
        return Self.stripRepetition(response.content)
    }

    /// Graph-backed advice that can be checked afterwards.
    ///
    /// Same model, sampling, and token budget as `advise` above — the only
    /// differences are the citation contract in the instructions and the
    /// structured return type. Takes the packer's `PackedContext` rather than a
    /// bare string so the caller validates against exactly what was sent, with
    /// no chance of the manifest and the prompt drifting apart.
    func adviseGrounded(question: String,
                        decisions: [DecisionSummary],
                        experiences: [ExperienceSummary],
                        reminders: [ReminderSummary],
                        events: [EventSummary],
                        people: [PersonProfileSummary],
                        packedContext: MemoryGraphContextPacker.PackedContext)
    async throws -> (answer: GroundedAnswer, report: GroundingReport) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw AdviceError.noQuestion }
        guard Self.answerModel.isAvailable else { throw AdviceError.modelUnavailable }

        let session = LanguageModelSession(
            model: Self.answerModel,
            instructions: Prompts.groundedAdvisorInstructions
        )
        let response = try await session.respond(
            to: Prompts.advisorPrompt(
                question: q,
                context: Self.context(
                    decisions: decisions, experiences: experiences,
                    reminders: reminders, events: events, people: people,
                    graphContext: packedContext.text
                )
            ),
            generating: GroundedAnswer.self,
            options: GenerationOptions(sampling: Self.answerSampling, maximumResponseTokens: 400)
        )
        var answer = response.content
        answer.answer = Self.stripRepetition(answer.answer)
        return (answer, GroundingValidator.validate(answer, against: packedContext))
    }

    func answerWhoIs(question: String, people: [PersonProfileSummary]) async throws -> String {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw AdviceError.noQuestion }
        // No known person was resolved for this question — answer this
        // deterministically instead of handing the model an empty PEOPLE
        // block and a name it has never seen: asked about someone not in
        // People (e.g. "who is Connor" when Connor was never saved), the
        // model fabricated a relationship and even cited an entry that never
        // mentioned the name at all. There is no real answer to retrieve
        // here, so don't give the model a chance to invent one.
        guard !people.isEmpty else {
            return "I don't have anyone by that name in your People list."
        }
        guard Self.answerModel.isAvailable else { throw AdviceError.modelUnavailable }

        let session = LanguageModelSession(
            model: Self.answerModel,
            instructions: Prompts.whoIsInstructions
        )
        let response = try await session.respond(
            to: Prompts.whoIsPrompt(question: q, context: Self.context(decisions: [], experiences: [], people: people)),
            options: GenerationOptions(sampling: Self.answerSampling, maximumResponseTokens: 200)
        )
        return Self.stripRepetition(response.content)
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
            ),
            options: GenerationOptions(sampling: Self.answerSampling, maximumResponseTokens: 400)
        )
        return Self.stripRepetition(response.content)
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
    /// characters once a journal has any real history, pushing a single request
    /// past the on-device model's 4096-token window with zero room left to
    /// generate a response — a hard failure, not a quality tradeoff.
    ///
    /// Repeatedly recalibrated from real on-device overflows and repeatedly
    /// still not enough: 6,000 chars measured at 4,091 tokens, then a
    /// 2,000-char budget (with advisorInstructions independently shortened
    /// 2,628 → 1,206 chars) STILL overflowed at 4,090 tokens on the exact
    /// same question that had worked moments earlier — with no code change
    /// to context size in between, only the addition of greedy sampling
    /// (see `advise()`'s now-explicit `maximumResponseTokens`, the more
    /// likely actual cause). Without a real on-device tokenizer, character
    /// budgets for this densely-structured content are fundamentally an
    /// approximation, not a guarantee. Cut much harder than the arithmetic
    /// alone would suggest, since the arithmetic has been wrong multiple
    /// times now.
    private static let contextCharacterBudget = 1_200

    /// Assembles blocks in priority order (People and the graph context are
    /// ground truth and usually small; Decisions/Experiences are the bulky,
    /// lower-precision fallback), keeping only what fits the budget. Unlike a
    /// skip-if-it-doesn't-fit approach, the first block that would exceed the
    /// remaining budget is TRUNCATED to fill exactly what's left, not skipped
    /// whole — a single oversized block (the graph context, in practice) must
    /// never be able to silently consume the entire budget on its own while
    /// contributing nothing, and the total must never exceed the budget
    /// regardless of how large any individual block grows.
    private static func fitToBudget(_ blocks: [String]) -> String {
        guard !blocks.isEmpty else { return "(no past decisions or experiences on record)" }
        var kept: [String] = []
        var remaining = contextCharacterBudget
        for block in blocks {
            let separatorCost = kept.isEmpty ? 0 : 2   // "\n\n"
            let available = remaining - separatorCost
            guard available > 0 else { break }
            if block.count <= available {
                kept.append(block)
                remaining -= (block.count + separatorCost)
            } else {
                kept.append(truncatedToLineBoundary(block, available: available))
                remaining = 0
            }
        }
        return kept.joined(separator: "\n\n")
    }

    /// Cuts `block` to fit `available` characters at the last complete line
    /// rather than an arbitrary character position — a raw `prefix` landed
    /// mid-word on a real evidence line ("...Argument with Alex ab…"), a
    /// dangling, unfinished sentence right in the model's own input. Dropping
    /// the partial trailing line entirely keeps every line the model actually
    /// sees intact, at the cost of a little unused budget.
    private static func truncatedToLineBoundary(_ block: String, available: Int) -> String {
        let prefix = String(block.prefix(available))
        guard let lastNewline = prefix.lastIndex(of: "\n") else {
            return prefix + "…"   // no line break to snap to — best effort
        }
        return String(prefix[..<lastNewline]) + "\n…"
    }

    private static func clip(_ text: String, max: Int = 240) -> String {
        text.count <= max ? text : String(text.prefix(max)) + "…"
    }

    /// Small on-device models can fall into a self-copy loop, especially when
    /// the input context itself is a repetitive list (several "X is Y of Z"
    /// PEOPLE lines) — restating what it already saw is a very-high-probability
    /// continuation, and it can keep doing that until maximumResponseTokens
    /// cuts it off. Neither greedy nor a small top-k sampling reliably
    /// prevents this (both were tried on-device; both still looped, just with
    /// a different period), and the framework exposes no repetition-penalty
    /// option to lean on instead. Detect it deterministically: once any
    /// sentence repeats one already seen in this response, generation has
    /// gone degenerate — keep only what came before the first repeat.
    static func stripRepetition(_ text: String) -> String {
        let pieces = text.components(separatedBy: ". ")
        guard pieces.count > 1 else { return text }
        var seen = Set<String>()
        var kept: [String] = []
        for piece in pieces {
            let normalized = piece.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // Short fragments (e.g. "Yes" or a lone number) are common enough
            // on their own that seeing one twice isn't evidence of a loop.
            guard normalized.count > 12 else {
                kept.append(piece)
                continue
            }
            guard !seen.contains(normalized) else { break }
            seen.insert(normalized)
            kept.append(piece)
        }
        var result = kept.joined(separator: ". ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return text }
        // A piece that isn't the array's true last element (i.e. truncation
        // cut the loop short) never carried the source text's own trailing
        // punctuation — restore it so the result still reads as a complete
        // sentence rather than stopping mid-thought.
        if let last = result.last, !".!?".contains(last) {
            result += "."
        }
        return result
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
        QueryIntentDraft(tone: "", domain: "", topicKeywords: [], sortOrder: "recent", limit: 0, questionType: "generic")
    }

    func eventAdvice(event: String,
                     when: Date,
                     weather: String?,
                     decisions: [DecisionSummary],
                     experiences: [ExperienceSummary]) async throws -> String {
        "Before \(event): last time something similar came up it went reasonably well — repeat what worked, and jot down two questions to ask."
    }

    func answerWhoIs(question: String, people: [PersonProfileSummary]) async throws -> String {
        people.isEmpty
            ? "I don't have anyone by that name in your People list."
            : "Drawing on your People profile — " + people.map(\.text).joined(separator: " ")
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
