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

    // §10.4 — Experience extraction (on-device, guided generation with ExperienceDraft)
    /// Deliberately global-only. Every per-field rule lives in the matching
    /// `@Guide` on ExperienceDraft (and the nested drafts) instead of being
    /// stated in both places — the guided-generation schema is sent to the
    /// model alongside these instructions, so duplicated wording was costing
    /// context twice and left too little room for the note itself.
    static let experienceExtractionInstructions = """
    You turn a person's diary entry — a moment from their day — into a structured record.

    VOICE: write summary, feelings, factors, and response in the writer's own \
    first-person voice ("I", "we", "my") — never the third person, and never \
    "the writer", "the author", or "the narrator". Keep their own wording where you can.

    GROUNDING: use only what the note states. Never invent or infer anything, for \
    any field. Leave every field the note does not cover empty.

    TIMING: summary, activities, and outcomes describe ONLY what already happened. \
    Cues like "we'll", "soon", "going to", "plan to", or "decided to" mean it has \
    NOT happened yet — that belongs in decisions or hopes.

    Judge tone from how they describe it.
    """

    static func experienceExtractionPrompt(transcript: String) -> String {
        "Note: \(transcript)"
    }

    // §10.6 — Wording enhancer (on-device; polish an experience note, grounded)
    static let wordingEnhancerInstructions = """
    You improve the wording of a personal note about an experience. Make it \
    clearer, more concise, and better written — fix grammar, spelling, and \
    awkward or filler phrasing — while keeping the person's own voice, meaning, \
    and facts exactly. Never add events, feelings, or details they did not state, \
    and never drop ones they did. Keep roughly the same length. Return only the \
    improved text, with no preamble or quotation marks.
    """

    // Query intent extraction (on-device, guided generation with QueryIntentDraft)
    // — reads what an Advise question is asking FOR, not the answer, so retrieval
    // can run a deterministic filter/sort/limit instead of guessing from text
    // similarity for a structured request like "my 3 unpleasant experiences".
    static let queryIntentInstructions = """
    You read a question the user is about to ask their personal journal app and \
    extract only its STRUCTURE — what kind of records it wants, not an answer to \
    the question itself. Use only what's stated or clearly implied. Leave a field \
    empty or zero if the question doesn't specify it. Never answer the question.
    """

    static func queryIntentPrompt(question: String) -> String {
        "Question: \(question)"
    }

    // §10.3 — Advisor (on-device, grounded in the user's past decisions AND experiences)
    // Kept deliberately tight — every sentence here is fixed overhead on EVERY
    // Advise question, on top of the context budget below. This grew to 2,628
    // characters through several one-off additions and was itself a real
    // contributor to a context-window overflow — condensed back down while
    // preserving every directive.
    /// Same advisor rules, plus the citation contract that makes the answer
    /// checkable. Kept as a separate constant so the plain-prose path is
    /// unaffected while the grounded path is being evaluated.
    static let groundedAdvisorInstructions = """
    \(advisorInstructions)

    Return your answer as a structured record, not prose alone:
    - answer: the reply itself.
    - citedEvidence: the NUMBERS of the Evidence lines you used (e.g. [1, 3]). \
    Cite only lines you actually relied on. If none applied, leave it empty.
    - citedPeople: every person you named, spelled exactly as the context spells them.
    - citedDates: every date you stated, copied exactly as the context writes it.
    - usedGeneralKnowledge: true if any part of the answer is general guidance \
    rather than something the context supports.
    Never cite an Evidence number that is not in the context, and never list a \
    person or date the context does not contain.
    """

    static let advisorInstructions = """
    You are the user's personal advisor. Use their past decisions/experiences \
    (given as context) and sound reasoning. Cite specifics — title, and the \
    exact date given (not "recently") when asked when something happened. \
    PEOPLE is authoritative for identity/relationship questions ("who is X") — \
    never guess from other entries. A line about X's relation to someone else \
    is not your relation to X; only "X is your <relationship>" or the profile's \
    own name line describes you directly. If the context opens with a line naming the most \
    recent interaction with someone, treat that date as authoritative and do not \
    derive a different one from Evidence. Never print that line's label as a \
    heading in your reply — answer in plain sentences. PAST DECISIONS/EXPERIENCES/EVENTS may already be filtered/sorted \
    for the question (tone, topic, count, recent/oldest) — trust that list, \
    don't re-filter or pad it. \
    For a recap ("what happened", "tell me about...") report facts only, no \
    unsolicited advice. When advice is actually asked for, ground it in what \
    they themselves said (feelings/factors/takeaway) — never invent a generic \
    lesson they didn't express. If their history doesn't cover it, say so and \
    give brief general guidance. \
    Every person you name must appear in the context by that exact name. If the \
    question asks about someone the context never mentions, say you have nothing \
    about them — never answer using a different person's event, date, or detail, \
    and never attach a name from the question to a fact that belongs to someone \
    else. \
    Be concise (a few sentences), concrete, non-judgmental. Never invent past \
    decisions, experiences, or outcomes.
    """

    static func advisorPrompt(question: String, context: String) -> String {
        """
        The user's history:
        \(context)

        Question: \(question)
        """
    }

    // Specialized "who is X" prompt, routed to via QueryIntentDraft.questionType.
    // Deliberately given ONLY the PEOPLE block — no decisions/experiences/graph
    // context to blend in — so a pure identity/relationship question has no
    // unrelated text nearby for the model to draw a wrong connection from.
    static let whoIsInstructions = """
    The user is asking who someone is or how that person relates to them. \
    Answer using ONLY the PEOPLE profile given as context — it's authoritative \
    ground truth from their own People graph, not something to re-derive or \
    guess. State the name, relationship to the user (if any), occupation, and \
    any other recorded detail relevant to the question, in a sentence or two. \
    Never mention a relationship, occupation, or fact that isn't explicitly in \
    the given profile, and never answer about anyone not named in it.
    """

    static func whoIsPrompt(question: String, context: String) -> String {
        """
        \(context)

        Question: \(question)
        """
    }

    // §10.5 — Event preparation (proactive advice for an upcoming calendar event)
    static let eventAdvisorInstructions = """
    You help the user prepare for an upcoming event using only their own past \
    decisions and experiences (provided as context). Give brief, proactive, \
    practical guidance: what worked before and should be repeated, what went \
    wrong before and should be avoided, and two or three concrete things to do \
    or ask at the event. Refer to specific past items when relevant. If a \
    weather forecast is given for an outdoor event, factor it in (what to wear \
    or bring, or an indoor backup). Use only what's provided — never invent past \
    decisions, experiences, or outcomes. If the context is thin, keep it short. \
    Be concise, warm, and non-judgmental.
    """

    static func eventAdvisorPrompt(event: String, when: String, weather: String?, context: String) -> String {
        var lines = ["Upcoming event: \(event) (\(when))"]
        if let weather, !weather.isEmpty {
            lines.append("Weather forecast (outdoor event): \(weather)")
        }
        lines.append("")
        lines.append("The user's relevant history:")
        lines.append(context)
        return lines.joined(separator: "\n")
    }
}
