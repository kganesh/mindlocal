import Foundation

/// Detects people named in an Advise question and renders their actual People-graph
/// data (aliases, relationships) as ground truth for the advisor. Without this, the
/// advisor only had semantic text search over Decisions/Experiences/Reminders/Events
/// — a "who is X" question had no access to the real stored relationship at all, so
/// the model would guess from whatever loosely-related entry text got retrieved
/// instead of using the fact that was actually recorded.
enum PersonContextBuilder {
    /// Lowercased, punctuation-stripped words — so matching doesn't care about
    /// "Dr." vs "Dr" or a trailing "?", and a short alias can't match inside an
    /// unrelated word (word-boundary, not substring).
    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Every known person whose name or an alias appears in the question as a
    /// contiguous word phrase.
    @MainActor
    static func mentionedPeople(in question: String, among people: [Person]) -> [Person] {
        let questionWords = words(question)
        guard !questionWords.isEmpty else { return [] }
        return people.filter { person in
            person.normalizedNames.contains { candidate in
                let candidateWords = words(candidate)
                guard !candidateWords.isEmpty, candidateWords.count <= questionWords.count else { return false }
                return (0...(questionWords.count - candidateWords.count)).contains { start in
                    Array(questionWords[start..<start + candidateWords.count]) == candidateWords
                }
            }
        }
    }

    /// A person's display name, with an explicit "(this is you)" tag when they're
    /// the Me anchor — the graph can hold a separate node for the same real
    /// person as their own full name (e.g. a "Me" anchor plus a "Ganesh Kolekar"
    /// node created from a third-person mention), and without this tag the
    /// advisor has no way to know they're the same individual, so it reasons
    /// about "the author" as someone distinct from a graph person named after
    /// them.
    private static func identifiedName(_ person: Person) -> String {
        person.isMe ? "\(person.fullDisplayName) (this is you, the diary's author)" : person.fullDisplayName
    }

    /// A natural-language profile for one person: their aliases and every
    /// relationship edge they're part of, rendered from their own perspective —
    /// the same "subject is <type> of object" convention used on their People page.
    @MainActor
    static func profile(for person: Person, relationships: [PersonRelationship]) -> String {
        var lines = ["\(identifiedName(person)):"]
        if !person.aliases.isEmpty {
            lines.append("  Also called: \(person.aliases.joined(separator: ", "))")
        }
        let edges = relationships.filter { $0.subject === person || $0.object === person }
        if edges.isEmpty {
            lines.append("  No recorded relationship to anyone else in People.")
        } else {
            for edge in edges {
                let isSubject = edge.subject === person
                let label = isSubject ? edge.type.label : edge.type.inverseLabel
                let other = (isSubject ? edge.object : edge.subject).map(identifiedName) ?? "someone"
                lines.append("  \(person.name) is \(label) of \(other).")
            }
        }
        return lines.joined(separator: "\n")
    }
}
