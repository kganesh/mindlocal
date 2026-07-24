import Foundation

/// Resolves a natural-language time phrase ("next Tuesday", "in two weeks", "Aug
/// 15 at 2pm") extracted from a diary entry into an absolute date. Uses
/// `NSDataDetector` rather than asking the on-device LLM to compute dates —
/// relative-date arithmetic is exactly what small on-device models get wrong, and
/// this is the same system parser iOS itself uses for "tap to add to Calendar" in
/// Messages/Mail/Notes. Anchored to the system clock at call time (matches how
/// entries are almost always resolved same-day as written).
enum AppointmentDateResolver {
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue
    )

    /// Nil if no confident date/time could be parsed from the phrase.
    static func resolve(_ phrase: String) -> Date? {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let detector else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let match = detector.firstMatch(in: trimmed, options: [], range: range)
        return match?.date
    }
}
