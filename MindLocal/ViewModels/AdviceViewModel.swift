import Foundation
import Observation

/// Drives the Advise flow (spec §9): ask a question, get an answer grounded in
/// the user's saved decisions.
@Observable
@MainActor
final class AdviceViewModel {
    enum Phase: Equatable {
        case idle
        case thinking
        case answer(String)
        case error(String)
    }

    var question: String = ""
    private(set) var phase: Phase = .idle

    private let advisor: AdvisingServicing
    let speech: SpeechServicing

    init(advisor: AdvisingServicing = AdviceService(),
         speech: SpeechServicing = SpeechService()) {
        self.advisor = advisor
        self.speech = speech
    }

    var canAsk: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && phase != .thinking
    }

    var answer: String? {
        if case .answer(let text) = phase { return text }
        return nil
    }

    /// Reads the structure of `question` (a tone/topic/count/sort it implies) so
    /// the caller can run a deterministic retrieval pass before asking. Falls
    /// back to "no structure" on any failure — that's a safe degradation, since
    /// it just means retrieval relies on semantic search alone, same as before
    /// this existed.
    func extractIntent(for question: String) async -> QueryIntentDraft {
        (try? await advisor.extractIntent(from: question))
            ?? QueryIntentDraft(tone: "", domain: "", topicKeywords: [], sortOrder: "recent", limit: 0)
    }

    func ask(decisions: [DecisionSummary], experiences: [ExperienceSummary],
             reminders: [ReminderSummary] = [], events: [EventSummary] = [],
             people: [PersonProfileSummary] = []) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        phase = .thinking
        do {
            phase = .answer(try await advisor.advise(
                question: q, decisions: decisions, experiences: experiences,
                reminders: reminders, events: events, people: people
            ))
        } catch AdviceError.modelUnavailable {
            phase = .error("Apple Intelligence isn't available right now. Please try again later.")
        } catch {
            phase = .error("Couldn't get an answer. Please try again.")
        }
    }

    func clear() {
        question = ""
        phase = .idle
    }
}
