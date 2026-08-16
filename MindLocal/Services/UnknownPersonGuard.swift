import Foundation

/// Refuses questions about a person the app has never heard of, before the
/// model is given a chance to answer them.
///
/// Reported case: "Did Nora's birthday happen last week?" — Nora is in neither
/// People nor any entry. The context contained only Akhil's birthday, and the
/// model answered "Nora's birthday is scheduled for August 2, 2026", taking
/// Akhil's date and attaching a name that appears nowhere. Substitution like
/// that is the worst shape a wrong answer takes: fluent, specific, and
/// impossible to tell from a right one without checking the source.
///
/// `WhoIsQuestionDetector` already covers "who is X". This covers the much
/// larger set of questions that merely *mention* an unknown person while asking
/// something else, which is where the substitution risk actually lives.
///
/// Narrow on purpose. It fires only on a capitalised possessive ("Nora's"),
/// which in English is almost always a named person, and only when that name
/// resolves to nobody at all.
enum UnknownPersonGuard {

    /// Capitalised words that take a possessive but are not people.
    private static let notPeople: Set<String> = [
        "my", "his", "her", "their", "its", "your", "our", "everyone", "someone",
        "today", "tomorrow", "yesterday", "monday", "tuesday", "wednesday",
        "thursday", "friday", "saturday", "sunday", "january", "february",
        "march", "april", "may", "june", "july", "august", "september",
        "october", "november", "december", "week", "month", "year", "company",
        "team", "family", "work", "god", "doctor", "manager", "boss"
    ]

    /// Capitalised possessive names in `query`, e.g. "Nora's birthday" -> Nora.
    ///
    /// The first word is NOT skipped, even though sentence-initial capitals
    /// carry no signal on their own. A question can open with the name
    /// ("Anne-Marie's visit"), and the openers that would otherwise slip
    /// through — "Did", "What", "How" — do not take a possessive anyway. The
    /// ones that do, "Today's" and "August's", are in the stop list.
    static func possessiveNames(in query: String) -> [String] {
        let cleaned = query.replacingOccurrences(of: "\u{2019}", with: "'")
        let words = cleaned.split(separator: " ").map(String.init)
        var found: [String] = []

        for word in words {
            let trimmed = word.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"()"))
            guard trimmed.hasSuffix("'s") || trimmed.hasSuffix("'S") else { continue }
            let name = String(trimmed.dropLast(2))
            guard name.count > 1,
                  let first = name.first, first.isUppercase,
                  name.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "'" }),
                  !notPeople.contains(name.lowercased())
            else { continue }
            found.append(name)
        }
        return found
    }

    /// A deterministic reply when the question names someone unknown, or nil
    /// when every name in it resolves and the question can proceed normally.
    ///
    /// Distinguishes the same two cases as the "who is" path: a name the
    /// journal has written about but never added to People gets its mentions
    /// cited; a name that appears nowhere gets a plain refusal. Neither
    /// involves a model call, so neither can invent anything.
    @MainActor
    static func refusal(for query: String,
                        people: [Person],
                        graph: MemoryGraph,
                        now: Date = .now) -> String? {
        for name in possessiveNames(in: query) {
            if people.contains(where: { $0.matches(name) }) { continue }
            if RelationshipType.role(forTerm: name) != nil { continue }

            if let mention = UnresolvedPersonFinder.find(name: name, in: graph, now: now) {
                return mention.answerText
            }
            return "I don't have anyone named \(name) in your People list, and your notes "
                 + "don't mention them, so I can't answer questions about them yet."
        }
        return nil
    }
}
