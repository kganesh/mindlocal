import Foundation
import FoundationModels

protocol ExtractionServicing: Sendable {
    func extract(from transcript: String) async throws -> DecisionDraft
    func extractExperience(from transcript: String) async throws -> ExperienceDraft
    func followUpQuestion(draftSummary: String, missingField: String) async throws -> String
}

enum ExtractionError: Error {
    case modelUnavailable
}

/// On-device extraction via Foundation Models guided generation (spec §5, §10.1–10.2).
final class ExtractionService: ExtractionServicing {

    func extract(from transcript: String) async throws -> DecisionDraft {
        guard SystemLanguageModel.default.isAvailable else {
            throw ExtractionError.modelUnavailable
        }
        let session = LanguageModelSession(
            model: .default,
            instructions: Prompts.extractionInstructions
        )
        let response = try await session.respond(
            to: Prompts.extractionPrompt(transcript: transcript),
            generating: DecisionDraft.self
        )
        return response.content
    }

    func extractExperience(from transcript: String) async throws -> ExperienceDraft {
        guard SystemLanguageModel.default.isAvailable else {
            throw ExtractionError.modelUnavailable
        }
        let session = LanguageModelSession(
            model: .default,
            instructions: Prompts.experienceExtractionInstructions
        )
        let response = try await session.respond(
            to: Prompts.experienceExtractionPrompt(transcript: transcript),
            generating: ExperienceDraft.self
        )
        return response.content
    }

    func followUpQuestion(draftSummary: String, missingField: String) async throws -> String {
        guard SystemLanguageModel.default.isAvailable else {
            throw ExtractionError.modelUnavailable
        }
        let session = LanguageModelSession(
            model: .default,
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
            decisions: [
                DecisionDraft(title: "Run before work", statement: "I decided to run before work instead of after.",
                              context: "", options: [], rationale: "Mornings are quieter and set up my day.",
                              domain: "health", stakes: "low")
            ]
        )
    }

    func followUpQuestion(draftSummary: String, missingField: String) async throws -> String {
        "What made you choose this option?"
    }
}
