import Foundation
import Observation

/// Drives the capture flow (spec §4): free-form input → extraction →
/// editable preview → max 2 follow-ups → save.
@Observable
@MainActor
final class CaptureViewModel {
    enum Phase: Equatable {
        case input                 // mic or text entry
        case extracting
        case preview               // editable DecisionDraft / ExperienceDraft
        case followUp(question: String, field: String)
        case nothingFound          // note contained no decision / experience
        case error(String)
    }

    /// What the capture is recording — a decision or a lived experience.
    enum Mode: String, CaseIterable, Identifiable {
        case decision, experience
        var id: String { rawValue }
        var label: String { self == .decision ? "Decision" : "Experience" }
    }

    var phase: Phase = .input
    var mode: Mode = .decision
    var typedText: String = ""
    var draft: DecisionDraft?
    var experienceDraft: ExperienceDraft?
    /// When the decision was made / the experience happened (editable in review).
    var occurredAt: Date = .now
    private var followUpsAsked = 0
    private let extraction: ExtractionServicing
    let speech: SpeechServicing

    init(extraction: ExtractionServicing = ExtractionService(),
         speech: SpeechServicing = SpeechService()) {
        self.extraction = extraction
        self.speech = speech
        // M1 acceptance: restore transcript lost to a crash.
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
            switch mode {
            case .decision:
                let extracted = try await extraction.extract(from: transcript)
                if extracted.isDecision {
                    draft = extracted
                    await advanceToPreviewOrFollowUp(transcript: transcript)
                } else {
                    phase = .nothingFound
                }
            case .experience:
                let extracted = try await extraction.extractExperience(from: transcript)
                if extracted.isExperience {
                    experienceDraft = extracted
                    phase = .preview
                } else {
                    phase = .nothingFound
                }
            }
        } catch ExtractionError.modelUnavailable {
            phase = .error("Apple Intelligence isn't available right now. Your note is saved as a draft.")
        } catch {
            phase = .error("Couldn't process the note. Your note is saved as a draft.")
        }
    }

    private func advanceToPreviewOrFollowUp(transcript: String) async {
        guard let draft else { return }
        let missing = draft.missingFields
        if followUpsAsked < 2, let field = missing.first {
            followUpsAsked += 1
            let summary = "\(draft.title): \(draft.statement)"
            if let q = try? await extraction.followUpQuestion(draftSummary: summary, missingField: field) {
                phase = .followUp(question: q, field: field)
                return
            }
        }
        phase = .preview
    }

    func answerFollowUp(_ answer: String, field: String) async {
        guard var d = draft else { return }
        switch field {
        case "rationale": d.rationale = answer
        case "options": d.options = [OptionDraft(text: answer, rejectedBecause: "")]
        default: break
        }
        draft = d
        // Re-check remaining fields (cap enforced in advance method).
        await advanceToPreviewOrFollowUp(transcript: typedText)
    }

    func skipFollowUp() {
        phase = .preview
    }

    /// Returns the Decision to insert; caller owns the ModelContext.
    func finalizeDecision() -> Decision? {
        guard let draft, draft.isDecision else { return nil }
        let transcript = typedText.isEmpty ? speech.transcript : typedText
        let decision = draft.toDecision(rawTranscript: transcript, occurredAt: occurredAt)
        DraftStore.clear()
        reset()
        return decision
    }

    /// Returns the Experience to insert; caller owns the ModelContext.
    func finalizeExperience() -> Experience? {
        guard let experienceDraft, experienceDraft.isExperience else { return nil }
        let transcript = typedText.isEmpty ? speech.transcript : typedText
        let experience = experienceDraft.toExperience(rawText: transcript, occurredAt: occurredAt)
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
        draft = nil
        experienceDraft = nil
        occurredAt = .now
        followUpsAsked = 0
        phase = .input
        // keep `mode` so the user stays in their chosen capture mode
    }
}
