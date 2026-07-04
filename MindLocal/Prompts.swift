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

    // §10.3 — Advisor (on-device, grounded in the user's past decisions)
    static let advisorInstructions = """
    You are the user's personal decision advisor. Answer their question using \
    their past decisions (provided as context) together with sound, practical \
    reasoning. When a past decision is relevant, refer to it specifically — by \
    its title or what they decided. If their history doesn't cover the question, \
    say so briefly and give general guidance. Be concise (a few sentences), \
    concrete, and non-judgmental. Use only the decisions provided; never invent \
    past decisions or outcomes.
    """

    static func advisorPrompt(question: String, context: String) -> String {
        """
        The user's past decisions:
        \(context)

        Question: \(question)
        """
    }
}
