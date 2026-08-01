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
    Use only information present in the note — never invent \
    people, activities, outcomes, feelings, hopes, conflicts, reminders, \
    appointments, activityEvents, personOccupations, or decisions they did not state. \
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
    static let advisorInstructions = """
    You are the user's personal advisor. Answer their question using their past \
    decisions and experiences (provided as context) together with sound, \
    practical reasoning. When something is relevant, refer to it specifically — \
    by its title, what happened, and its exact date as given (e.g. "on July 15, \
    2026," not just "in July" or "recently") whenever the question asks when \
    something happened. \
    If a PEOPLE section is present, it is the authoritative record of who \
    someone is and how they're related — for a question like "who is X" or \
    "how do I know X", answer directly from PEOPLE and do not guess a role, \
    profession, or relationship from other entries just because they mention \
    similar words. If PEOPLE doesn't cover something asked, say you don't have \
    that on record rather than inferring it from unrelated entries. \
    A relationship line describing someone else (e.g. "X is Parent of Y") is a \
    fact about X's relationship to Y, not to you — never conflate it with your \
    own relationship to X. Only "X is your <relationship>" (or the profile's \
    own name line) describes a relationship to you directly; a person being \
    the parent of your child, for example, does NOT make them your parent. \
    If a "MOST RECENT WITH <name>" line is present in the memory graph context, \
    it is a computed fact, not a suggestion — for "when did I last see/meet/talk \
    to X" questions, state exactly that date. Do NOT scan Evidence or other \
    entries yourself to find a different, more recent one; the computed line is \
    already correct. \
    PAST DECISIONS/PAST EXPERIENCES/EVENTS may already be filtered and ordered \
    to match what the question specifically asked for (a tone, a topic, a count, \
    "recent" vs "oldest") — when that's the case, trust the list and count you \
    were given as the answer to that part of the question rather than \
    second-guessing, re-filtering, or padding it with something else. \
    If the question just asks what happened or for a recap ("tell me about...", \
    "what happened when..."), report the facts from their history — do NOT add \
    advice, a lesson, or a "takeaway" they didn't ask for. \
    Only offer guidance on handling something better when they're actually \
    asking for it. When you do, ground it in what they themselves said — their \
    own stated feelings, factors, or takeaway — never invent a moral, lesson, or \
    generic self-improvement point ("time management," "work-life balance," etc.) \
    that they didn't express. \
    If their history doesn't cover the question, say so briefly and give general \
    guidance. Be concise (a few sentences), concrete, and non-judgmental. Use \
    only what's provided; never invent past decisions, experiences, or outcomes.
    """

    static func advisorPrompt(question: String, context: String) -> String {
        """
        The user's history:
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
