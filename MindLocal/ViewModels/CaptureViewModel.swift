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
    /// When the experience happened (editable in review).
    var occurredAt: Date = .now

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
        phase = .extracting
        do {
            let extracted = try await extraction.extractExperience(from: transcript)
            if extracted.isExperience {
                experienceDraft = extracted
                phase = .preview
            } else {
                phase = .nothingFound
            }
        } catch ExtractionError.modelUnavailable {
            phase = .error("Apple Intelligence isn't available right now. Your note is saved as a draft.")
        } catch {
            phase = .error("Couldn't process the note. Your note is saved as a draft.")
        }
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
        DraftStore.clear()
        reset()
        return experience
    }

    func discard() {
        DraftStore.clear()
        reset()
    }

    private func reset() {
        typedText = ""
        experienceDraft = nil
        occurredAt = .now
        phase = .input
    }
}
