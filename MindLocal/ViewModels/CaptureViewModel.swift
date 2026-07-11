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
    /// Role mentions the user identified in review → chosen person name.
    var peopleAssignments: [String: String] = [:]

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
            let extracted = try await extractWithRetry(transcript: transcript)
            if extracted.isExperience {
                experienceDraft = extracted
                phase = .preview
            } else {
                phase = .nothingFound
            }
        } catch ExtractionError.modelUnavailable {
            phase = .error("Apple Intelligence isn't available right now. Your note is saved as a draft.")
        } catch {
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

    /// Turns the underlying error into an actionable message. Matches on the
    /// error text so we don't hard-code FoundationModels' case names, and shows
    /// the raw reason in DEBUG so device testing reveals the exact cause.
    static func friendlyMessage(for error: Error) -> String {
        let detail = String(describing: error).lowercased()
        let base: String
        if detail.contains("guardrail") || detail.contains("safety") {
            base = "The on-device model declined this note (safety guardrail). Try rewording it."
        } else if detail.contains("context") || detail.contains("window") || detail.contains("exceeded") {
            base = "This entry is a bit long for on-device processing. Try splitting it into two shorter moments."
        } else if detail.contains("decod") || detail.contains("parse") {
            base = "The model couldn't structure this note cleanly — tap Try Again."
        } else {
            base = "Couldn't process the note."
        }
        #if DEBUG
        return "\(base)\n\n[\(error)]\n\nYour note is saved as a draft."
        #else
        return "\(base) Your note is saved as a draft."
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
        peopleAssignments = [:]
        phase = .input
    }
}
