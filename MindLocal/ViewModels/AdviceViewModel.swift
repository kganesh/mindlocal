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
    private var activeRequestID: UUID?

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

    func beginAsk() -> (id: UUID, question: String)? {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        let id = UUID()
        activeRequestID = id
        phase = .thinking
        return (id, q)
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

    func ask(requestID: UUID, question submittedQuestion: String,
             decisions: [DecisionSummary], experiences: [ExperienceSummary],
             reminders: [ReminderSummary] = [], events: [EventSummary] = [],
             people: [PersonProfileSummary] = [], graphContext: String = "") async {
        guard activeRequestID == requestID else { return }
        let q = submittedQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            activeRequestID = nil
            return
        }
        do {
            let answer = try await advisor.advise(
                question: q, decisions: decisions, experiences: experiences,
                reminders: reminders, events: events, people: people,
                graphContext: graphContext
            )
            guard activeRequestID == requestID else { return }
            activeRequestID = nil
            phase = .answer(answer)
        } catch AdviceError.modelUnavailable {
            guard activeRequestID == requestID else { return }
            activeRequestID = nil
            phase = .error("Apple Intelligence isn't available right now. Please try again later.")
        } catch {
            guard activeRequestID == requestID else { return }
            activeRequestID = nil
            phase = .error("\(ModelErrorReason.debugAnnotated(error)) Please try again.")
        }
    }

    func clear() {
        question = ""
        activeRequestID = nil
        phase = .idle
    }
}
