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
}

protocol AdvisingServicing: Sendable {
    /// Answers `question`, grounded in the user's past decisions and experiences.
    func advise(question: String,
                decisions: [DecisionSummary],
                experiences: [ExperienceSummary]) async throws -> String

    /// Proactive preparation advice for an upcoming event, grounded in the
    /// (already-filtered, relevant) decisions and experiences.
    func eventAdvice(event: String,
                     when: Date,
                     decisions: [DecisionSummary],
                     experiences: [ExperienceSummary]) async throws -> String
}

enum AdviceError: Error {
    case modelUnavailable
    case noQuestion
}

/// On-device advisor (spec §10.3) via Foundation Models, grounded in past
/// decisions passed as context. (Semantic retrieval via `Decision.embedding`
/// is a later milestone; for now the most recent decisions are used.)
final class AdviceService: AdvisingServicing {

    func advise(question: String,
                decisions: [DecisionSummary],
                experiences: [ExperienceSummary]) async throws -> String {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw AdviceError.noQuestion }
        guard SystemLanguageModel.default.isAvailable else { throw AdviceError.modelUnavailable }

        let session = LanguageModelSession(
            model: .default,
            instructions: Prompts.advisorInstructions
        )
        let response = try await session.respond(
            to: Prompts.advisorPrompt(question: q, context: Self.context(decisions: decisions, experiences: experiences))
        )
        return response.content
    }

    func eventAdvice(event: String,
                     when: Date,
                     decisions: [DecisionSummary],
                     experiences: [ExperienceSummary]) async throws -> String {
        guard SystemLanguageModel.default.isAvailable else { throw AdviceError.modelUnavailable }

        let session = LanguageModelSession(
            model: .default,
            instructions: Prompts.eventAdvisorInstructions
        )
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let response = try await session.respond(
            to: Prompts.eventAdvisorPrompt(
                event: event,
                when: formatter.string(from: when),
                context: Self.context(decisions: decisions, experiences: experiences)
            )
        )
        return response.content
    }

    /// Formats the most recent decisions and experiences into a compact context.
    static func context(decisions: [DecisionSummary], experiences: [ExperienceSummary]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        var blocks: [String] = []

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
                if !e.factors.isEmpty { parts.append("   Because: \(clip(e.factors))") }
                if !e.learning.isEmpty { parts.append("   Takeaway: \(clip(e.learning))") }
                return parts.joined(separator: "\n")
            }
            blocks.append("PAST EXPERIENCES (pleasant to recreate, unpleasant to handle better):\n" + lines.joined(separator: "\n\n"))
        }

        return blocks.isEmpty ? "(no past decisions or experiences on record)" : blocks.joined(separator: "\n\n")
    }

    private static func clip(_ text: String, max: Int = 240) -> String {
        text.count <= max ? text : String(text.prefix(max)) + "…"
    }
}

/// Deterministic mock for previews and tests.
final class MockAdviceService: AdvisingServicing {
    func advise(question: String,
                decisions: [DecisionSummary],
                experiences: [ExperienceSummary]) async throws -> String {
        if decisions.isEmpty && experiences.isEmpty {
            return "You don't have any saved decisions or experiences yet, so I can only offer general guidance."
        }
        return "Drawing on your history — the choices you've made and what you've lived through — I'd lean this way."
    }

    func eventAdvice(event: String,
                     when: Date,
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
            createdAt: experience.createdAt,
            title: experience.title,
            summary: experience.summary,
            feelings: experience.feelings,
            tone: experience.tone.label,
            factors: experience.factors,
            learning: experience.learning,
            domain: experience.domain.label,
            tags: experience.tags
        )
    }
}

extension DecisionSummary {
    @MainActor
    init(_ decision: Decision) {
        self.init(
            id: decision.id,
            createdAt: decision.createdAt,
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
