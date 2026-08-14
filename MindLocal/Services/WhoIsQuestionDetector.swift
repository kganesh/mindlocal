import Foundation

/// Deterministic backstop for "who is X" questions about someone who isn't in
/// People.
///
/// Routing to the safe identity path depends on `QueryIntentDraft.questionType
/// == "who_is"`, which is produced by a model call that can misclassify — and
/// whose failure fallback is `"generic"`, the unsafe path. That default was
/// written when the draft only carried tone/topic/sort, where degrading to "no
/// structure" genuinely was safe; it stopped being safe once questionType
/// joined the same struct. The observed result: "who is Tommy?" (a name never
/// saved) reached the generic pipeline with full graph context and came back
/// "Tommy is your brother."
///
/// This catches that case without a model call. Kept deliberately narrow — it
/// only fires when NO known person resolved, so a legitimate question about a
/// real person is never diverted, and "who is coming to dinner?" is excluded by
/// the stop list rather than being answered "I don't have anyone by that name."
enum WhoIsQuestionDetector {

    /// Openers that make a question purely about identity.
    private static let identityPrefixes = [
        "who is ", "who's ", "who was ", "who are ", "who were ",
        "how am i related to ", "how is ", "how am i connected to "
    ]

    /// Words that mean the question is about an action or a group, not a name —
    /// "who is coming", "who is my manager". A relationship term like "my
    /// manager" resolves through the People graph or not at all; either way it
    /// is not a bare unknown name and shouldn't be short-circuited here.
    private static let notANameStarters: Set<String> = [
        "coming", "going", "joining", "attending", "invited", "available",
        "free", "driving", "responsible", "involved", "helping", "working",
        "my", "the", "that", "this", "he", "she", "they", "it", "there",
        "in", "at", "on", "with", "a", "an", "everyone", "anyone", "someone"
    ]

    /// The candidate name when `query` asks who a specific, name-like person is.
    /// nil when the question isn't identity-shaped, or when what follows isn't a
    /// plausible name.
    static func candidateName(in query: String) -> String? {
        let normalized = query
            .lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let prefix = identityPrefixes.first(where: { normalized.hasPrefix($0) }) else {
            return nil
        }

        let remainder = String(normalized.dropFirst(prefix.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: " ?.!,"))
        guard !remainder.isEmpty else { return nil }

        // A name is short. Anything longer is a sentence, not a person.
        let words = remainder.split(separator: " ").map(String.init)
        guard (1...3).contains(words.count) else { return nil }
        guard let first = words.first, !notANameStarters.contains(first) else { return nil }

        // Letters only (allowing hyphens/apostrophes for O'Brien, Anne-Marie).
        let allowed = CharacterSet.letters.union(CharacterSet(charactersIn: "-'"))
        guard words.allSatisfy({ $0.unicodeScalars.allSatisfy(allowed.contains) }) else {
            return nil
        }
        return remainder
    }

    /// True when the question asks who a specific named person is. Callers must
    /// additionally confirm no known person resolved before short-circuiting —
    /// this says nothing about whether the name is known.
    static func looksLikeIdentityQuestion(_ query: String) -> Bool {
        candidateName(in: query) != nil
    }
}
