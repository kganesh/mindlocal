import Foundation
import FoundationModels

protocol ExtractionServicing: Sendable {
    func extract(from transcript: String) async throws -> DecisionDraft
    func extractExperience(from transcript: String) async throws -> ExperienceDraft
    func followUpQuestion(draftSummary: String, missingField: String) async throws -> String
    /// Rewrites a note more clearly without changing meaning or facts.
    func enhanceWording(_ text: String) async throws -> String
}

enum ExtractionError: Error {
    case modelUnavailable
}

/// On-device extraction via Foundation Models guided generation (spec §5, §10.1–10.2).
final class ExtractionService: ExtractionServicing {

    /// The diary transforms the user's own words into a structured record, so we
    /// use permissive guardrails — the default filter false-positives on ordinary
    /// journal content (e.g. work stress) and refuses with "may contain sensitive
    /// content", which would otherwise block the entry entirely.
    private static let model = SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    )

    func extract(from transcript: String) async throws -> DecisionDraft {
        guard Self.model.isAvailable else {
            throw ExtractionError.modelUnavailable
        }
        let session = LanguageModelSession(
            model: Self.model,
            instructions: Prompts.extractionInstructions
        )
        let response = try await session.respond(
            to: Prompts.extractionPrompt(transcript: transcript),
            generating: DecisionDraft.self
        )
        return response.content
    }

    func extractExperience(from transcript: String) async throws -> ExperienceDraft {
        guard Self.model.isAvailable else {
            throw ExtractionError.modelUnavailable
        }
        let session = LanguageModelSession(
            model: Self.model,
            instructions: Prompts.experienceExtractionInstructions
        )
        let response = try await session.respond(
            to: Prompts.experienceExtractionPrompt(transcript: transcript),
            generating: ExperienceDraft.self
        )
        return response.content
    }

    func enhanceWording(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        guard Self.model.isAvailable else {
            throw ExtractionError.modelUnavailable
        }
        let session = LanguageModelSession(
            model: Self.model,
            instructions: Prompts.wordingEnhancerInstructions
        )
        let response = try await session.respond(to: trimmed)
        return response.content
    }

    func followUpQuestion(draftSummary: String, missingField: String) async throws -> String {
        guard Self.model.isAvailable else {
            throw ExtractionError.modelUnavailable
        }
        let session = LanguageModelSession(
            model: Self.model,
            instructions: Prompts.followUpInstructions
        )
        let response = try await session.respond(
            to: Prompts.followUpPrompt(draftSummary: draftSummary, missingField: missingField)
        )
        return response.content
    }
}

/// Deterministic mock for tests and previews.
final class MockExtractionService: ExtractionServicing {
    func extract(from transcript: String) async throws -> DecisionDraft {
        DecisionDraft(
            title: "Chose the cheaper contractor",
            statement: "I decided to hire the cheaper contractor for the kitchen.",
            context: "Two quotes, 30% price gap, tight budget this quarter.",
            options: [OptionDraft(text: "Premium contractor", rejectedBecause: "Over budget")],
            rationale: "Budget matters more than schedule right now.",
            valuesPrioritized: ["financial safety"],
            valuesTradedOff: ["schedule"],
            domain: "money",
            stakes: "medium"
        )
    }

    func extractExperience(from transcript: String) async throws -> ExperienceDraft {
        ExperienceDraft(
            title: "Great morning run by the river",
            summary: "I went for a run along the river at sunrise and felt fantastic.",
            feelings: "Energized, calm, proud.",
            tone: "pleasant",
            factors: "Quiet trail, cool weather, going before work.",
            response: "Kept an easy pace and stopped to watch the sunrise.",
            learning: "Morning runs set up my whole day — do this more often.",
            tags: ["health", "morning"],
            domain: "health",
            people: ["Sam"],
            activities: ["morning run", "watched the sunrise"],
            outcomes: ["felt energized all day"],
            hopes: ["wants to run three mornings a week"],
            conflicts: [],
            reminders: [],
            appointments: [],
            decisions: [
                DecisionDraft(title: "Run before work", statement: "I decided to run before work instead of after.",
                              context: "", options: [], rationale: "Mornings are quieter and set up my day.",
                              valuesPrioritized: ["energy"], valuesTradedOff: ["sleep-in"],
                              domain: "health", stakes: "low")
            ]
        )
    }

    func followUpQuestion(draftSummary: String, missingField: String) async throws -> String {
        "What made you choose this option?"
    }

    func enhanceWording(_ text: String) async throws -> String {
        text.isEmpty ? text : text + " (polished)"
    }
}
