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
    static let experienceExtractionInstructions = """
    You turn a person's diary entry — a moment or experience from their day — into \
    a structured record. Write the summary, feelings, factors, and response in the \
    diary writer's own first-person voice ("I", "we", "my"), the way they wrote it — \
    never in the third person and never refer to them as "the writer", "the author", \
    "the narrator", or "they". Extract the people involved, the activities they did, \
    the outcomes/results, their emotions, any forward-looking wants/wishes/hopes, and \
    the themes. For people, list only OTHER people the writer mentions by name or \
    relationship (e.g. Lilly, Maya, my manager) — never include the diary writer \
    themselves, and never "I", "me", "the writer", "the narrator", or "the author". \
    If they mention any decisions they made, extract those into the decisions list; \
    otherwise leave it empty. If they describe an argument, disagreement, fight, or \
    tension with a specific person, extract it into the conflicts list — who it was \
    with, what it was about, how they felt, and whether it was resolved, unresolved, \
    or ongoing; otherwise leave conflicts empty. A merely unpleasant event with no \
    interpersonal disagreement is NOT a conflict. An argument or disagreement is a \
    conflict — put it ONLY in conflicts, never under activities or outcomes. \
    If they say something like "remind me to ask my doctor about X" or "next time I \
    see my manager, bring up Y" — a concrete action item tied to a FUTURE interaction \
    with a specific named person — extract it into reminders (who it's about, and \
    what to remember), never into hopes. A general want or wish with no specific \
    person and no next-interaction framing ("I hope things get better") stays in \
    hopes, not reminders. \
    If they mention a specific upcoming appointment, meeting, or scheduled visit \
    WITH a stated date or time ("next Tuesday", "in two weeks", "the 15th at 2pm"), \
    extract it into appointments — who it's with, a short title, and the date/time \
    exactly as they said it. Keep their original wording for the date/time; do NOT \
    compute or normalize it into a calendar date yourself. If no specific date or \
    time is mentioned, it is NOT an appointment — leave it in reminders or hopes \
    instead. \
    If they describe an activity that ALREADY happened WITH a specific named \
    person ("met David for coffee", "took Mom to her appointment"), extract it \
    into activityEvents — a short title, who it was with, and what time it \
    happened exactly as they said it (empty if no time was mentioned). Do NOT \
    include an activity done alone or with an unnamed group ("the team", \
    "friends") — those stay in activities only, never in activityEvents. \
    If they explicitly state a specific named person's occupation or job title \
    ("David, a nurse, ...", "my manager Sarah is a director at..."), extract it \
    into personOccupations — the person and their occupation exactly as stated. \
    Do NOT infer or guess an occupation from context (a role reference like \
    "my manager" is a relationship, not necessarily their job title unless the \
    note itself says so) — only what's explicitly stated. \
    If they state that a specific named person likes or dislikes something \
    ("Akhil loves chocolate ice cream cake", "Gayatri can't stand cilantro"), \
    extract it into personPreferences — the person, the specific thing, and \
    whether it's a like or dislike. This must be an actual, ongoing preference \
    they stated, NOT how they reacted to a single one-off moment — "Akhil was \
    excited about the ice cream today" describes one moment, not a preference; \
    do not extract a preference from it. \
    Use only information present in the note — never invent \
    people, activities, outcomes, feelings, hopes, conflicts, reminders, \
    appointments, activityEvents, personOccupations, personPreferences, or \
    decisions they did not state. \
    Distinguish what actually happened from what the person only planned, intends, or \
    decided to do later. The summary, activities, and outcomes must describe ONLY \
    actions that already occurred. Never report a planned, intended, or not-yet-done \
    action as completed — cues like "we'll", "soon", "going to", "plan to", or \
    "decided to (do later)" mean it has NOT happened yet. Such intentions belong in \
    decisions or hopes, never in outcomes or the summary. \
    If they state what time something happened, exact ("4 o'clock", "4pm") or \
    approximate ("in the afternoon", "this morning", "around noon"), keep that \
    time reference in the summary — it's part of what happened, not a detail \
    to compress away. \
    If a field is not mentioned, leave it empty. Judge the tone (pleasant, \
    unpleasant, or mixed) from how they describe it. Keep their own wording where \
    possible. Title is max 8 words.
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
    static let advisorInstructions = """
    You are the user's personal advisor. Use their past decisions/experiences \
    (given as context) and sound reasoning. Cite specifics — title, and the \
    exact date given (not "recently") when asked when something happened. \
    PEOPLE is authoritative for identity/relationship questions ("who is X") — \
    never guess from other entries. A line about X's relation to someone else \
    is not your relation to X; only "X is your <relationship>" or the profile's \
    own name line describes you directly. A "MOST RECENT WITH <name>" line is a \
    computed fact — state it directly, don't re-derive a different date from \
    Evidence. PAST DECISIONS/EXPERIENCES/EVENTS may already be filtered/sorted \
    for the question (tone, topic, count, recent/oldest) — trust that list, \
    don't re-filter or pad it. \
    For a recap ("what happened", "tell me about...") report facts only, no \
    unsolicited advice. When advice is actually asked for, ground it in what \
    they themselves said (feelings/factors/takeaway) — never invent a generic \
    lesson they didn't express. If their history doesn't cover it, say so and \
    give brief general guidance. \
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
