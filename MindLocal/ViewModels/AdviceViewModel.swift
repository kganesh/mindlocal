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
    #if DEBUG
    /// The exact context string assembled for the last question — lets you see
    /// what the on-device model actually saw, for debugging an answer that
    /// looks wrong or inconsistent. Never built in release builds.
    private(set) var debugContext: String?
    /// Grounding findings for the last question, when the Settings toggle
    /// routed it through the grounded path. nil when that path wasn't used.
    private(set) var debugGroundingReport: GroundingReport?
    #endif

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
            ?? QueryIntentDraft(tone: "", domain: "", topicKeywords: [], sortOrder: "recent", limit: 0, questionType: "generic")
    }

    func ask(requestID: UUID, question submittedQuestion: String,
             decisions: [DecisionSummary], experiences: [ExperienceSummary],
             reminders: [ReminderSummary] = [], events: [EventSummary] = [],
             people: [PersonProfileSummary] = [], graphContext: String = "",
             packedContext: MemoryGraphContextPacker.PackedContext? = nil) async {
        let q = submittedQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            activeRequestID = nil
            return
        }
        await complete(
            requestID: requestID,
            debugContext: {
                AdviceService.context(
                    decisions: decisions, experiences: experiences,
                    reminders: reminders, events: events,
                    people: people, graphContext: graphContext
                )
            },
            answer: {
                // packedContext non-nil means the Settings toggle asked for the
                // grounded path. It carries the manifest the report is checked
                // against, so the answer is validated against exactly the
                // context that produced it.
                guard let packedContext else {
                    return try await self.advisor.advise(
                        question: q, decisions: decisions, experiences: experiences,
                        reminders: reminders, events: events, people: people,
                        graphContext: graphContext
                    )
                }
                let (grounded, report) = try await self.advisor.adviseGrounded(
                    question: q, decisions: decisions, experiences: experiences,
                    reminders: reminders, events: events, people: people,
                    packedContext: packedContext
                )
                #if DEBUG
                self.debugGroundingReport = report
                #endif
                return grounded.answer
            }
        )
    }

    /// Routed to whenever `QueryIntentDraft.questionType == "who_is"`, whether
    /// or not `PersonContextBuilder.mentionedPeople` actually resolved anyone.
    /// `people` non-empty: answers from their People profile alone, skipping
    /// decisions/experiences/graph context entirely — a pure identity
    /// question doesn't need it, and excluding it keeps unrelated retrieved
    /// text from getting blended in. `people` empty: `AdviceService.
    /// answerWhoIs` answers deterministically with no model call, rather than
    /// let the generic pipeline's noisy context give the model room to invent
    /// a relationship for a name it's never seen.
    func askWhoIs(requestID: UUID, question submittedQuestion: String,
                  people: [PersonProfileSummary]) async {
        let q = submittedQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            activeRequestID = nil
            return
        }
        await complete(
            requestID: requestID,
            debugContext: { AdviceService.context(decisions: [], experiences: [], people: people) },
            answer: { try await self.advisor.answerWhoIs(question: q, people: people) }
        )
    }

    /// Shared request lifecycle for every "ask a question, get an answer"
    /// path: ignore stale completions, record the debug context, and map
    /// failures to the same user-facing errors — so adding another dedicated
    /// question type doesn't mean re-copying this plumbing.
    private func complete(requestID: UUID,
                          debugContext buildDebugContext: () -> String,
                          answer produceAnswer: () async throws -> String) async {
        guard activeRequestID == requestID else { return }
        #if DEBUG
        debugContext = buildDebugContext()
        debugGroundingReport = nil
        #endif
        do {
            let answer = try await produceAnswer()
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

    /// Publishes an answer this app computed itself, with no model call.
    /// Used where the truthful answer is fully determined by the data — e.g. a
    /// name the journal mentions but People doesn't contain, where handing the
    /// question to the model is exactly what produced "Tommy is your brother".
    func answerDirectly(requestID: UUID, text: String, debugContext: String = "") async {
        await complete(
            requestID: requestID,
            debugContext: { debugContext },
            answer: { text }
        )
    }

    func clear() {
        question = ""
        activeRequestID = nil
        phase = .idle
    }
}
