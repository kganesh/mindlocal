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

protocol AdvisingServicing: Sendable {
    /// Answers `question`, grounded in the user's past decisions.
    func advise(question: String, history: [DecisionSummary]) async throws -> String
}

enum AdviceError: Error {
    case modelUnavailable
    case noQuestion
}

/// On-device advisor (spec §10.3) via Foundation Models, grounded in past
/// decisions passed as context. (Semantic retrieval via `Decision.embedding`
/// is a later milestone; for now the most recent decisions are used.)
final class AdviceService: AdvisingServicing {

    func advise(question: String, history: [DecisionSummary]) async throws -> String {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw AdviceError.noQuestion }
        guard SystemLanguageModel.default.isAvailable else { throw AdviceError.modelUnavailable }

        let session = LanguageModelSession(
            model: .default,
            instructions: Prompts.advisorInstructions
        )
        let response = try await session.respond(
            to: Prompts.advisorPrompt(question: q, context: Self.context(from: history))
        )
        return response.content
    }

    /// Formats the most recent decisions into a compact context block.
    static func context(from history: [DecisionSummary]) -> String {
        guard !history.isEmpty else { return "(no past decisions on record)" }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"

        let recent = history.sorted { $0.createdAt > $1.createdAt }.prefix(15)
        return recent.enumerated().map { index, decision in
            var lines = ["\(index + 1). [\(decision.domain), \(decision.stakes) stakes, \(formatter.string(from: decision.createdAt))] \(decision.title)"]
            if !decision.statement.isEmpty { lines.append("   Decided: \(clip(decision.statement))") }
            if !decision.rationale.isEmpty { lines.append("   Because: \(clip(decision.rationale))") }
            if let outcome = decision.outcome, !outcome.isEmpty { lines.append("   Outcome: \(clip(outcome))") }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    private static func clip(_ text: String, max: Int = 240) -> String {
        text.count <= max ? text : String(text.prefix(max)) + "…"
    }
}

/// Deterministic mock for previews and tests.
final class MockAdviceService: AdvisingServicing {
    func advise(question: String, history: [DecisionSummary]) async throws -> String {
        if history.isEmpty {
            return "You don't have any saved decisions yet, so I can only offer general guidance."
        }
        return "Looking at your past decisions, you tend to weigh budget and long-term growth heavily. For this, I'd lean the same way."
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
