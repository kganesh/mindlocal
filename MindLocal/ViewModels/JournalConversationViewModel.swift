import Foundation
import Observation

/// Drives the nightly voice check-in: the app speaks a short, fixed sequence of
/// questions, listens to each spoken answer, then extracts a structured journal
/// entry from the whole conversation. Fully on-device.
@Observable
@MainActor
final class JournalConversationViewModel {
    enum Phase: Equatable {
        case ready
        case asking(Int)     // question index
        case processing
        case saved
        case error(String)
    }

    let questions = [
        "How was your day?",
        "Who did you spend time with?",
        "How did things turn out — any wins or setbacks?",
        "Anything on your mind — hopes, worries, or decisions you made?"
    ]

    var phase: Phase = .ready
    var occurredAt: Date = .now
    private(set) var answers: [String] = []
    private(set) var builtExperience: Experience?
    /// "Who is this?" answers for the confirm step (mention → chosen person name).
    var peopleAssignments: [String: String] = [:]

    let speech: SpeechServicing
    let speaker: SpeechSpeaker
    private let extraction: ExtractionServicing

    init(speech: SpeechServicing = SpeechService(),
         speaker: SpeechSpeaker? = nil,
         extraction: ExtractionServicing = ExtractionService()) {
        self.speech = speech
        self.speaker = speaker ?? SpeechSpeaker()
        self.extraction = extraction
    }

    var currentIndex: Int {
        if case .asking(let i) = phase { return i } else { return 0 }
    }
    var isLastQuestion: Bool { currentIndex >= questions.count - 1 }

    func start() async {
        answers = []
        await ask(0)
    }

    /// Speak a question, then (after it finishes, to avoid echo) start listening.
    private func ask(_ index: Int) async {
        phase = .asking(index)
        speaker.speak(questions[index])
        while speaker.isSpeaking { try? await Task.sleep(for: .milliseconds(120)) }
        if await speech.requestAuthorization() {
            try? await speech.startRecording()
        }
    }

    /// Capture the current answer, then move to the next question or finish.
    func advance() async {
        captureCurrentAnswer()
        if currentIndex < questions.count - 1 {
            await ask(currentIndex + 1)
        } else {
            await finish()
        }
    }

    /// End the check-in early with whatever's been said so far.
    func endEarly() async {
        captureCurrentAnswer()
        await finish()
    }

    private func captureCurrentAnswer() {
        speech.stopRecording()
        answers.append(speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func finish() async {
        speaker.stop()
        phase = .processing
        let transcript = combinedTranscript
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .error("Nothing to save — try again when you're ready to talk.")
            return
        }
        do {
            let draft = try await extraction.extractExperience(from: transcript)
            guard draft.isExperience else {
                phase = .error("I couldn't find anything to journal from that.")
                return
            }
            let experience = draft.toExperience(rawText: transcript, occurredAt: occurredAt)
            experience.decisions = draft.decisions
                .filter { $0.isDecision }
                .map { $0.toDecision(rawTranscript: transcript, occurredAt: occurredAt) }
            builtExperience = experience
            phase = .saved
        } catch ExtractionError.modelUnavailable {
            phase = .error("Apple Intelligence isn't available right now.")
        } catch {
            phase = .error("Couldn't process your day. Please try again.")
        }
    }

    /// The user's own words only — the app's scripted questions ("How was your
    /// day?") are prompts, not part of the entry, so they're excluded from both
    /// the saved note and what the model extracts from.
    var combinedTranscript: String {
        answers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    func cancel() {
        speaker.stop()
        speech.stopRecording()
    }
}
