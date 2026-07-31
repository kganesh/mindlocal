import Foundation

/// Resolves a time-of-day phrase ("4 o'clock", "in the afternoon", empty) from a
/// past activity into an absolute `Date` on an already-known day. Unlike
/// `AppointmentDateResolver` (which resolves *which day* a future phrase like
/// "next Tuesday" means, anchored to "now"), the day here is never ambiguous —
/// it's the diary entry's own date — so this only ever resolves the time
/// component, and always relative to that entry's day, never "now".
enum ActivityTimeResolver {
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue
    )

    /// Fixed representative hours for a stated-but-imprecise time of day. Chosen
    /// as reasonable midpoints, not measured — only ever used to place an event
    /// on the right side of "before/after" on its day, never presented as exact.
    private static let buckets: [(keywords: [String], hour: Int)] = [
        (["morning"], 9),
        (["afternoon", "midday", "noon"], 14),
        (["evening"], 18),
        (["night", "tonight"], 21)
    ]

    /// - Returns: an absolute date on `day`, and whether the time is a guess
    ///   (a bucket, or no time stated at all) rather than something the user
    ///   actually said.
    static func resolve(timePhrase: String, on day: Date) -> (date: Date, isApproximate: Bool) {
        let trimmed = timePhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.current

        // Bucket words checked BEFORE the exact-time parser: NSDataDetector
        // doesn't just fail on a bare "this morning" — it resolves that into
        // some guessed concrete time too (anchored to "now"), which would
        // otherwise be mistaken for a real stated clock time and reported as
        // precise when it was never anything more than a vague part of the day.
        let lowered = trimmed.lowercased()
        if let bucket = buckets.first(where: { bucket in bucket.keywords.contains { lowered.contains($0) } }) {
            let combined = calendar.date(bySettingHour: bucket.hour, minute: 0, second: 0, of: day) ?? day
            return (combined, true)
        }

        if !trimmed.isEmpty, let exact = exactTime(from: trimmed, calendar: calendar) {
            let combined = calendar.date(
                bySettingHour: exact.hour, minute: exact.minute, second: 0, of: day
            ) ?? day
            return (combined, false)
        }

        // No time stated, or a phrase we don't recognize — place it at a neutral
        // hour on the known day rather than refusing to create the event at all.
        let combined = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        return (combined, true)
    }

    /// Extracts just an hour/minute from a phrase like "4 o'clock" or "4:30pm" —
    /// reuses `NSDataDetector`'s well-tested time parsing for the TIME portion
    /// only; the DATE portion of whatever it resolves against "now" is discarded
    /// since we already know the real day independently.
    private static func exactTime(from phrase: String, calendar: Calendar) -> (hour: Int, minute: Int)? {
        guard let detector else { return nil }
        let range = NSRange(phrase.startIndex..<phrase.endIndex, in: phrase)
        guard let match = detector.firstMatch(in: phrase, options: [], range: range),
              let date = match.date else { return nil }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }
        return (hour, minute)
    }
}
