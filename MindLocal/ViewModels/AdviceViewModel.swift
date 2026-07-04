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

    init(advisor: AdvisingServicing = AdviceService()) {
        self.advisor = advisor
    }

    var canAsk: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && phase != .thinking
    }

    var answer: String? {
        if case .answer(let text) = phase { return text }
        return nil
    }

    func ask(history: [DecisionSummary]) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        phase = .thinking
        do {
            phase = .answer(try await advisor.advise(question: q, history: history))
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
