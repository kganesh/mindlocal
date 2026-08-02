import Foundation
import FoundationModels

/// Guided-generation target for the STRUCTURE of an Advise question — not an
/// answer, just what's being asked for (a tone filter, a topic, a count, a sort
/// direction), so retrieval can run a deterministic filter/sort/limit instead of
/// relying on embedding similarity to guess at a structured request like "my 3
/// unpleasant experiences recently". Every field can come back empty/zero for a
/// genuinely open-ended question — that just means no structured match is added,
/// and the existing semantic retrieval covers it exactly as before.
@Generable
struct QueryIntentDraft: Equatable {
    @Guide(description: "Tone filter, if the question asks about a specific kind of experience. One of: pleasant, unpleasant, mixed. Empty if not tone-specific.")
    var tone: String

    @Guide(description: "Domain filter, if the question is about a specific area of life. One of: career, money, health, family, work, other. Empty if not domain-specific.")
    var domain: String

    @Guide(description: "Short topic or keyword phrases from the question to match against entry tags, titles, or activities (e.g. 'birthday party', 'performance review'). Empty array if the question isn't about a specific recurring topic.")
    var topicKeywords: [String]

    @Guide(description: "Sort intent. One of: recent (most recent first), oldest (earliest first), none (order isn't implied). Prefer recent if the question looks back but doesn't specify a direction.")
    var sortOrder: String

    @Guide(description: "How many items the question asks for, if a specific count is stated (e.g. 'my 3 worst...' -> 3, 'the last one' -> 1). 0 if no count is stated.")
    var limit: Int

    // .anyOf hard-constrains the generated value to exactly one of these two
    // strings (unlike every other field above, which is merely described) —
    // routing compares this with `==`, and a free-text description alone let
    // the model return something like "Who is" or "identity" that silently
    // never matched, always falling through to the generic pipeline.
    @Guide(description: "What kind of question this is — used to route to a dedicated prompt instead of the generic one. 'who_is' if it's ONLY asking who someone is or how they're related to the user (e.g. 'who is Akhil', 'how am I related to Priya', 'tell me about Sam') — not if it also asks for advice, a recap, or anything beyond identity. 'generic' for everything else, including when unsure.", .anyOf(["who_is", "generic"]))
    var questionType: String
}

extension QueryIntentDraft {
    /// Whether this extracted anything actionable. Deliberately excludes
    /// `sortOrder` alone — a bare recency preference with no filter/count isn't
    /// enough to justify a structured pass; the model's `sortOrder` guess can be
    /// noisy even on genuinely open-ended questions.
    var hasStructure: Bool {
        !tone.isEmpty || !domain.isEmpty || !topicKeywords.isEmpty || limit > 0
    }
}
