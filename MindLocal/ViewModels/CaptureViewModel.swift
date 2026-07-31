import Foundation
import Observation

/// Drives the single capture flow: the user describes an experience (voice or
/// text); the AI extracts the experience plus any decisions they mention, then
/// shows an editable preview to save.
@Observable
@MainActor
final class CaptureViewModel {
    enum Phase: Equatable {
        case input                 // mic or text entry
        case extracting
        case preview               // editable ExperienceDraft (+ extracted decisions)
        case nothingFound          // note described no experience
        case error(String)
    }

    var phase: Phase = .input
    var typedText: String = ""
    var experienceDraft: ExperienceDraft?
    /// Appointments detected with a resolved date, shown as "Add to Events" cards
    /// in review. Removed from this list once added or dismissed; never affects
    /// the saved Experience directly (appointments become standalone `Event`s).
    var appointmentCandidates: [AppointmentCandidate] = []
    /// Past activities with a specific named person, shown as the same kind of
    /// "Add to Events" card as appointments. Resolved against `occurredAt` at
    /// submit time — like appointments, not reactive to a later edit of "When
    /// it happened" in review.
    var activityEventCandidates: [ActivityEventCandidate] = []
    /// When the experience happened (editable in review).
    var occurredAt: Date = .now
    /// Role mentions the user identified in review → chosen person name.
    var peopleAssignments: [String: String] = [:]
    /// Optional place the moment happened (editable in input/review).
    var location: String = ""
    var latitude: Double? = nil
    var longitude: Double? = nil
    /// True once extraction has failed, so we can offer to save the raw note.
    var canSaveRaw = false

    private let extraction: ExtractionServicing
    let speech: SpeechServicing

    init(extraction: ExtractionServicing = ExtractionService(),
         speech: SpeechServicing = SpeechService()) {
        self.extraction = extraction
        self.speech = speech
        // Restore transcript lost to a crash.
        if let pending = DraftStore.load(), !pending.transcript.isEmpty {
            typedText = pending.transcript
        }
    }

    func persistWorkInProgress() {
        let text = speech.isRecording ? speech.transcript : typedText
        if !text.isEmpty { DraftStore.save(transcript: text) }
    }

    func submit() async {
        let transcript = typedText.isEmpty ? speech.transcript : typedText
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        DraftStore.save(transcript: transcript)
        canSaveRaw = false
        phase = .extracting
        do {
            let extracted = try await extractWithRetry(transcript: transcript)
            if extracted.isExperience {
                experienceDraft = extracted
                appointmentCandidates = AppointmentCandidate.candidates(from: extracted.appointments)
                activityEventCandidates = ActivityEventCandidate.candidates(from: extracted.activityEvents, day: occurredAt)
                phase = .preview
            } else {
                phase = .nothingFound
            }
        } catch ExtractionError.modelUnavailable {
            canSaveRaw = true
            phase = .error("Apple Intelligence isn't available right now. You can save this as a plain entry below.")
        } catch {
            canSaveRaw = true
            phase = .error(Self.friendlyMessage(for: error))
        }
    }

    /// Guided generation on a long, dense note occasionally fails transiently
    /// (malformed structured output, rate limits). Retry once before surfacing.
    private func extractWithRetry(transcript: String) async throws -> ExperienceDraft {
        do {
            return try await extraction.extractExperience(from: transcript)
        } catch ExtractionError.modelUnavailable {
            throw ExtractionError.modelUnavailable   // don't retry an unavailable model
        } catch {
            return try await extraction.extractExperience(from: transcript)
        }
    }

    /// Turns the underlying error into an actionable message, via the reason
    /// shared with other on-device generation call sites plus a capture-specific
    /// action ("your note is saved as a draft" — this flow never loses input).
    static func friendlyMessage(for error: Error) -> String {
        let detail = String(describing: error).lowercased()
        let action: String
        if detail.contains("refus") || detail.contains("guardrail")
            || detail.contains("sensitive") || detail.contains("safety") {
            action = " You can save it as a plain entry below, or reword the flagged part and try again."
        } else if detail.contains("exceededcontextwindow") || detail.contains("context window") {
            action = " Try splitting it into two shorter moments."
        } else if detail.contains("decod") || detail.contains("parse") {
            action = " Tap Try Again."
        } else {
            action = ""
        }
        #if DEBUG
        return "\(ModelErrorReason.describe(error))\(action)\n\n[\(error)]\n\nYour note is saved as a draft."
        #else
        return "\(ModelErrorReason.describe(error))\(action) Your note is saved as a draft."
        #endif
    }

    /// Builds the Experience (with any linked decisions) to insert; caller owns
    /// the ModelContext.
    func finalizeEntry() -> Experience? {
        guard let experienceDraft, experienceDraft.isExperience else { return nil }
        let transcript = typedText.isEmpty ? speech.transcript : typedText
        let experience = experienceDraft.toExperience(rawText: transcript, occurredAt: occurredAt)
        experience.decisions = experienceDraft.decisions
            .filter { $0.isDecision }
            .map { $0.toDecision(rawTranscript: transcript, occurredAt: occurredAt) }
        applyLocation(to: experience)
        DraftStore.clear()
        reset()
        return experience
    }

    /// Builds a plain journal entry straight from the note when AI extraction
    /// fails (e.g. a false-positive safety refusal), so the diary is never lost.
    /// The raw text still reads as a diary page; structured fields stay empty.
    func finalizeRawEntry() -> Experience {
        let transcript = typedText.isEmpty ? speech.transcript : typedText
        let draft = ExperienceDraft(
            title: Self.derivedTitle(from: transcript),
            summary: transcript, feelings: "", tone: "mixed", factors: "",
            response: "", learning: "", tags: [], domain: "other",
            people: [], activities: [], outcomes: [], hopes: [],
            conflicts: [], reminders: [], appointments: [], decisions: [],
            activityEvents: []
        )
        let experience = draft.toExperience(rawText: transcript, occurredAt: occurredAt)
        applyLocation(to: experience)
        DraftStore.clear()
        reset()
        return experience
    }

    private func applyLocation(to experience: Experience) {
        experience.location = location
        experience.latitude = latitude
        experience.longitude = longitude
    }

    private static func derivedTitle(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let words = firstLine.split(separator: " ").prefix(6).joined(separator: " ")
        return words.isEmpty ? "Journal entry" : words
    }

    func discard() {
        DraftStore.clear()
        reset()
    }

    private func reset() {
        typedText = ""
        experienceDraft = nil
        appointmentCandidates = []
        activityEventCandidates = []
        occurredAt = .now
        peopleAssignments = [:]
        location = ""
        latitude = nil
        longitude = nil
        canSaveRaw = false
        phase = .input
    }
}
