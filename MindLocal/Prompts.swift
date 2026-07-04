import Foundation

/// All model prompts live here (spec §10). Never inline prompt strings elsewhere.
enum Prompts {

    // §10.1 — Extraction (on-device, guided generation with DecisionDraft)
    static let extractionInstructions = """
    You extract structured decision records from a person's spoken or typed note.
    Use only information present in the note. Never invent options, reasons, or \
    context the person did not state. If a field is not mentioned, leave it empty.
    Keep the person's own wording where possible. Title is max 8 words.
    """

    static func extractionPrompt(transcript: String) -> String {
        "Note: \(transcript)"
    }

    // §10.2 — Follow-up question (on-device)
    static let followUpInstructions = """
    You ask exactly one short, conversational question to fill a missing field \
    in a decision record. Never ask about more than one field. Max 15 words.
    """

    static func followUpPrompt(draftSummary: String, missingField: String) -> String {
        """
        Decision so far: \(draftSummary)
        Missing field: \(missingField)
        """
    }

    // §10.3 / §10.5 (advisor, pattern summary) are M3 — added then.
}
