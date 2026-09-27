import Foundation

/// Reads the feeling in one sentence of an answer, so each line can carry the
/// same weather icon the Journal uses for an entry.
///
/// Keyword matching, not a model call. An answer is already the expensive part,
/// and a second round trip to label three sentences would be felt. The cost of
/// the cheap approach is that it returns nil often, which is the intended
/// behaviour: a sentence with no feeling in it gets a plain bullet rather than
/// a guess dressed up as a reading.
///
/// It does not understand negation. "Not a good day" reads as pleasant, and the
/// fix for that is a real classifier rather than a longer word list.
enum SentenceToneDetector {

    static func tone(of sentence: String) -> ExperienceTone? {
        let text = sentence.lowercased()
        let pleasantHits = pleasant.count { text.contains($0) }
        let unpleasantHits = unpleasant.count { text.contains($0) }

        if pleasantHits == 0 && unpleasantHits == 0 { return nil }
        if pleasantHits > unpleasantHits { return .pleasant }
        if unpleasantHits > pleasantHits { return .unpleasant }
        // Both, in equal measure. That is what mixed means.
        return .mixed
    }

    /// Stems rather than whole words, so "enjoy" catches "enjoyed" and
    /// "enjoying" without listing each. Kept to words that actually appear in
    /// journal writing.
    private static let pleasant = [
        "happy", "happier", "joy", "glad", "grateful", "gratitude",
        "enjoy", "love", "loved", "like", "fun", "laugh",
        "calm", "relax", "peace", "quiet", "rest", "refresh",
        "content", "satisfi", "proud", "accomplish", "achiev", "productive",
        "good", "great", "fantastic", "wonderful", "lovely", "excellent",
        "excite", "energ", "well spent", "better", "celebrat", "success"
    ]

    private static let unpleasant = [
        "sad", "upset", "angry", "anger", "annoy", "frustrat", "irritat",
        "stress", "anxious", "anxiety", "worry", "worried", "nervous",
        "tired", "exhaust", "drain", "overwhelm", "burnout",
        "difficult", "hard", "struggl", "tough", "problem", "issue",
        "argu", "conflict", "disagree", "tension",
        "disappoint", "regret", "guilt", "lonely", "alone",
        "bad", "worse", "worst", "unhappy", "miss"
    ]
}

private extension Array where Element == String {
    func count(where predicate: (String) -> Bool) -> Int {
        reduce(0) { predicate($1) ? $0 + 1 : $0 }
    }
}
