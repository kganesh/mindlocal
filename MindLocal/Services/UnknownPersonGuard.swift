import Foundation
import NaturalLanguage

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
/// Two detectors feed it. A capitalised possessive ("Nora's") is the strongest
/// signal English offers that a word names a person. Bare capitalised words
/// ("...for Nora happen") are weaker, so they are filtered hard before they can
/// cause a refusal.
///
/// The filter that does the real work is the last one: a candidate is only
/// refused when it appears NOWHERE in the graph — not as a person, not as an
/// entry, location, activity or domain title. That is what keeps a project name
/// or a place from being refused as if it were a stranger, and it states the
/// actual rule the guard enforces: refuse only when the app has nothing at all.
///
/// `NLTagger` is used to drop places and organisations, and for nothing else.
/// It is not reliable enough to *find* names — it tags "Nora" in "for Nora
/// happen" as OtherWord and a real person, "Rohan", as PlaceName. The second
/// misfire is harmless because known people are matched before the tagger runs.
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

    /// Words that are only capitalised because they start a sentence. Without
    /// these, "Did ..." and "When ..." become candidate names the moment bare
    /// capitalised words are considered.
    private static let sentenceOpeners: Set<String> = [
        "did", "do", "does", "what", "whats", "when", "where", "why", "how",
        "who", "whos", "was", "were", "is", "are", "am", "will", "would",
        "should", "could", "can", "shall", "may", "might", "must", "have",
        "has", "had", "tell", "show", "give", "find", "list", "remind",
        "the", "a", "an", "and", "or", "but", "if", "in", "on", "at", "to",
        "for", "with", "about", "last", "next", "this", "that", "these",
        "those", "there", "here", "yes", "no", "ok", "okay", "please"
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

    /// Bare capitalised words that could name a person.
    ///
    /// Much weaker evidence than a possessive, so three filters apply before a
    /// word survives: it must be capitalised and letter-only, it must not be a
    /// stop word or a sentence opener, and `NLTagger` must not have called it a
    /// place or an organisation. The tagger is used only to *exclude* — it is
    /// not dependable enough to decide that something is a name.
    static func capitalisedNames(in query: String) -> [String] {
        let cleaned = query.replacingOccurrences(of: "\u{2019}", with: "'")
        let excluded = placesAndOrganisations(in: cleaned)
        var found: [String] = []

        for word in cleaned.split(separator: " ").map(String.init) {
            var name = word.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"()'"))
            // "Nora's" has an *internal* apostrophe, so trimming leaves it
            // intact and it would be reported as a name distinct from "Nora".
            if name.lowercased().hasSuffix("'s") { name = String(name.dropLast(2)) }
            guard name.count > 1,
                  let first = name.first, first.isUppercase,
                  name.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "'" }),
                  !notPeople.contains(name.lowercased()),
                  !sentenceOpeners.contains(name.lowercased()),
                  !excluded.contains(name.lowercased())
            else { continue }
            found.append(name)
        }
        return found
    }

    /// Tokens the name tagger is confident are places or organisations.
    private static func placesAndOrganisations(in query: String) -> Set<String> {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = query
        var excluded: Set<String> = []
        tagger.enumerateTags(in: query.startIndex..<query.endIndex,
                             unit: .word, scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            if tag == .placeName || tag == .organizationName {
                excluded.insert(query[range].lowercased())
            }
            return true
        }
        return excluded
    }

    /// Every candidate, possessives first, de-duplicated case-insensitively.
    static func candidateNames(in query: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in possessiveNames(in: query) + capitalisedNames(in: query)
        where seen.insert(name.lowercased()).inserted {
            result.append(name)
        }
        return result
    }

    /// Whether the graph holds anything at all under this name — a person, an
    /// entry, a location, an activity, a domain. Matched on whole words so
    /// "Ana" doesn't match "Anaheim".
    static func graphMentions(_ name: String, in graph: MemoryGraph) -> Bool {
        let needle = name.lowercased()
        return graph.nodes.contains { node in
            node.title.lowercased()
                .split(whereSeparator: { !$0.isLetter && $0 != "-" && $0 != "'" })
                .contains { $0 == Substring(needle) }
        }
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
        for name in candidateNames(in: query) {
            if people.contains(where: { $0.matches(name) }) { continue }
            if RelationshipType.role(forTerm: name) != nil { continue }

            if let mention = UnresolvedPersonFinder.find(name: name, in: graph, now: now) {
                return mention.answerText
            }
            // Last gate, and the one that makes widening safe: if the graph
            // holds anything under this name — a project, a place, an activity
            // — the question is answerable and must not be refused. Only a name
            // the app has never seen in any form gets here.
            if graphMentions(name, in: graph) { continue }

            return "I don't have anyone named \(name) in your People list, and your notes "
                 + "don't mention them, so I can't answer questions about them yet."
        }
        return nil
    }
}
