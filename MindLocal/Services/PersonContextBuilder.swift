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
    static func profile(for person: Person, relationships: [PersonRelationship], now: Date = .now) -> String {
        var lines = ["\(identifiedName(person)):"]
        if !person.aliases.isEmpty {
            lines.append("  Also called: \(person.aliases.joined(separator: ", "))")
        }
        if !person.occupation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("  Occupation: \(person.occupation).")
        }
        if !person.likes.isEmpty {
            lines.append("  Likes: \(person.likes.joined(separator: ", ")).")
        }
        if !person.dislikes.isEmpty {
            lines.append("  Dislikes: \(person.dislikes.joined(separator: ", ")).")
        }
        // Stated as a computed fact rather than left for the model to read out
        // of Evidence — a "priorities for X's birthday" question produced a
        // hallucinated date ("July 28th, 2027") by conflating this person's
        // birthday event with a different, similarly-worded birthday event
        // for someone else nearby in the same list. Same rationale as
        // MOST RECENT WITH: a small on-device model is unreliable at picking
        // the right one of several similar dated lines; compute it instead.
        if let birthdate = person.birthdate,
           let nextBirthday = BirthdayEventDeriver.nextOccurrence(of: birthdate, from: now) {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            lines.append("  Upcoming birthday (computed, authoritative — state this date directly, do not derive a different one from Evidence below): \(formatter.string(from: nextBirthday)).")
        }
        let edges = relationships.filter { $0.subject === person || $0.object === person }
        if edges.isEmpty {
            lines.append("  No recorded relationship to anyone else in People.")
        } else {
            for edge in edges {
                let isSubject = edge.subject === person
                let label = isSubject ? edge.type.label : edge.type.inverseLabel
                let otherPerson = isSubject ? edge.object : edge.subject
                if let otherPerson, otherPerson.isMe {
                    // "X is Child of Ganesh Kolekar (this is you, the diary's
                    // author)." reads ambiguously — a model can misattribute the
                    // trailing "(this is you...)" tag to the sentence's own
                    // subject (X) rather than the nearer name it actually
                    // modifies (Ganesh), producing a wrong "X is the diary's
                    // author" answer. "X is your <relationship>." carries the
                    // same fact with no parenthetical to misparse.
                    lines.append("  \(person.name) is your \(label.lowercased()).")
                } else if person.isMe {
                    // This whole profile's header already says "(this is you,
                    // the diary's author)" — but every line beneath it was still
                    // "Ganesh is Spouse of X" in the third person, mixing a
                    // second-person header with a third-person body. That
                    // mismatch is what let the model inconsistently decide
                    // whether "Ganesh" and "you" were the same person from one
                    // run to the next, sometimes producing "Ganesh is your
                    // spouse" (as if married to himself). Keep the whole profile
                    // in second person when it's the reader's own.
                    let other = otherPerson.map(identifiedName) ?? "someone"
                    lines.append("  You are \(label) of \(other).")
                } else {
                    let other = otherPerson.map(identifiedName) ?? "someone"
                    lines.append("  \(person.name) is \(label) of \(other).")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
