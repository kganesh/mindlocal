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
    /// Appointments detected with a resolved date, offered as "Add to Events"
    /// cards on the saved screen. Never affects the saved Experience directly.
    /// Mutable so the view can remove a candidate once added or dismissed.
    var appointmentCandidates: [AppointmentCandidate] = []
    /// Past activities with a specific named person, offered as the same kind
    /// of "Add to Events" card as appointments — a nightly check-in answering
    /// "who did you spend time with?" is exactly the multi-activity daily-log
    /// case this is for.
    var activityEventCandidates: [ActivityEventCandidate] = []
    /// Occupations mentioned for specific named people, applied to their Person
    /// records at save time (only ever fills a currently-blank occupation).
    private(set) var personOccupations: [PersonOccupationDraft] = []
    /// Likes/dislikes mentioned for specific named people, applied at save time
    /// (prepended to that person's list, deduped).
    private(set) var personPreferences: [PersonPreferenceDraft] = []
    /// True when the entry was saved from the raw words because AI extraction
    /// failed (e.g. a safety-filter refusal on a heavy entry) — so the check-in
    /// never loses what the user said. Drives a note on the saved screen.
    private(set) var savedWithoutAI = false
    /// "Who is this?" answers for the confirm step (mention → chosen person name).
    var peopleAssignments: [String: String] = [:]
    /// The current question's answer — typed, pasted, or dictated. Speech streams
    /// into this while recording; the user can also edit it directly.
    var currentAnswer: String = ""

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
        currentAnswer = ""
        speaker.speak(questions[index])
        while speaker.isSpeaking { try? await Task.sleep(for: .milliseconds(120)) }
        if await speech.requestAuthorization() {
            try? await speech.startRecording()
        }
    }

    /// Toggle dictation for the current question (so the user can also just type).
    func toggleMic() async {
        if speech.isRecording {
            speech.stopRecording()
        } else if await speech.requestAuthorization() {
            try? await speech.startRecording()
        }
    }

    func stopRecording() { speech.stopRecording() }

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
        let typed = currentAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        let spoken = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        answers.append(typed.isEmpty ? spoken : typed)
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
            experience.kind = .dailyLog
            experience.decisions = draft.decisions
                .filter { $0.isDecision }
                .map { $0.toDecision(rawTranscript: transcript, occurredAt: occurredAt) }
            builtExperience = experience
            appointmentCandidates = AppointmentCandidate.candidates(from: draft.appointments)
            activityEventCandidates = ActivityEventCandidate.candidates(from: draft.activityEvents, day: occurredAt)
            personOccupations = draft.personOccupations
            personPreferences = draft.personPreferences
            savedWithoutAI = false
            phase = .saved
        } catch {
            // Extraction failed — a safety-filter refusal, an unavailable model, or
            // a transient error. Never drop the user's words: save them as a plain
            // entry and let the saved screen explain it wasn't auto-summarized.
            builtExperience = Self.rawExperience(from: transcript, occurredAt: occurredAt)
            savedWithoutAI = true
            phase = .saved
        }
    }

    /// A plain journal entry straight from the transcript, used when AI extraction
    /// can't run so the check-in still preserves what was said.
    private static func rawExperience(from transcript: String, occurredAt: Date) -> Experience {
        let draft = ExperienceDraft(
            title: derivedTitle(from: transcript),
            summary: transcript, feelings: "", tone: "mixed", factors: "",
            response: "", learning: "", tags: [], domain: "other",
            people: [], activities: [], outcomes: [], hopes: [],
            conflicts: [], reminders: [], appointments: [], decisions: [],
            activityEvents: [], personOccupations: [], personPreferences: []
        )
        let experience = draft.toExperience(rawText: transcript, occurredAt: occurredAt)
        experience.kind = .dailyLog
        return experience
    }

    private static func derivedTitle(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let words = firstLine.split(separator: " ").prefix(6).joined(separator: " ")
        return words.isEmpty ? "Journal entry" : words
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
