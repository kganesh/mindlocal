import Foundation
import SwiftData

/// Resolves raw people mentions (e.g. "Sam", "mom") to `Person` graph nodes,
/// matching by name/alias and creating a node for anyone new. Deterministic;
/// de-dupes within a batch. Interactive disambiguation of same-name people
/// (the "which Lilly?" case) and relationship edges come in the next phase.
enum PersonResolver {
    /// Resolves mentions to Person nodes. `assignments` maps a mention (usually a
    /// role like "principal engineer") to the person name the user picked in the
    /// "Who's who?" review — that person gets the mention added as an alias so it
    /// auto-resolves next time. Unassigned role references are skipped (not
    /// auto-created as "principal engineer" people).
    @MainActor
    static func resolve(_ mentions: [String], assignments: [String: String] = [:], in context: ModelContext) -> [Person] {
        var pool = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        let relationships = (try? context.fetch(FetchDescriptor<PersonRelationship>())) ?? []
        let me = pool.first { $0.isMe }
        var result: [Person] = []

        func add(_ person: Person) {
            if !result.contains(where: { $0 === person }) { result.append(person) }
        }
        func findOrCreate(named name: String) -> Person {
            if let match = pool.first(where: { $0.matches(name) }) { return match }
            let person = Person(name: name)
            context.insert(person)
            pool.append(person)
            return person
        }

        for raw in mentions {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            // 0. User answered the confirm step for this mention.
            if let assigned = assignments[name] {
                let target = assigned.trimmingCharacters(in: .whitespacesAndNewlines)
                if target.isEmpty { continue }   // explicitly skipped / "not a person"
                let person = findOrCreate(named: target)
                if !person.matches(name) { person.aliases.append(name) }
                // A confirmed kinship term ("my sister" → Emma) also becomes a
                // relationship edge to Me, so the graph fills in as you journal.
                if let role = kinshipRole(for: name) {
                    let anchor = me ?? Person.fetchOrCreateMe(in: context)
                    if anchor !== person {
                        let linked = relationships.contains { e in
                            e.type == role &&
                            ((e.subject === person && e.object === anchor) ||
                             (e.subject === anchor && e.object === person))
                        }
                        if !linked {
                            context.insert(PersonRelationship(subject: person, type: role, object: anchor))
                        }
                    }
                }
                add(person)
                continue
            }

            // Skip groups/plurals and generic/self references.
            guard isLikelyPerson(name) else { continue }

            // 1. Direct name / alias match.
            if let match = pool.first(where: { $0.matches(name) }) {
                add(match)
                continue
            }
            // 2. Relative term via the graph ("mom" → parent-of-Me → Lilly).
            if let me, let role = RelationshipType.role(forTerm: name),
               let person = personInRole(role, of: me, relationships: relationships) {
                if !person.matches(name) { person.aliases.append(name) }
                add(person)
                continue
            }
            // 3. A role or bare kinship reference with no assignment — needs
            // identifying; skip rather than create a "manager"/"sister" node. It
            // will be asked again the next time it appears in an entry.
            if isRoleReference(name) || isKinshipTerm(name) { continue }

            // 4. New named person.
            let person = Person(name: name)
            context.insert(person)
            pool.append(person)
            add(person)
        }
        return result
    }

    /// Role/title/generic-descriptor words. A mention containing one is a role
    /// reference ("my manager", "principal engineer") that should be tied to a
    /// specific person rather than becoming its own node.
    private static let roleWords: Set<String> = [
        "manager", "boss", "engineer", "director", "lead", "colleague", "coworker",
        "co-worker", "teammate", "mentor", "advisor", "adviser", "supervisor",
        "recruiter", "client", "customer", "coach", "therapist", "doctor", "nurse",
        "teacher", "professor", "principal", "staff", "senior", "junior", "architect",
        "designer", "analyst", "developer", "consultant", "founder", "ceo", "cto",
        "vp", "head", "chief", "assistant", "intern", "partner", "colleague"
    ]

    static func isRoleReference(_ raw: String) -> Bool {
        let words = Set(raw.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "-" })
            .map(String.init))
        return !words.isDisjoint(with: roleWords)
    }

    /// Bare kinship terms — a specific person referred to only by relationship
    /// ("my sister", "mom"). Like roles, these are identified once (via the
    /// confirm step) rather than becoming a node literally named "sister".
    private static let kinshipWords: Set<String> = [
        "mom", "mum", "mommy", "mother", "dad", "daddy", "father", "parent",
        "sister", "brother", "sibling", "wife", "husband", "spouse", "fiance",
        "fiancee", "son", "daughter", "child", "grandma", "grandmother", "grandpa",
        "grandfather", "granddad", "granny", "aunt", "auntie", "uncle", "niece",
        "nephew", "cousin", "godmother", "godfather", "stepmom", "stepdad",
        "mother-in-law", "father-in-law", "sister-in-law", "brother-in-law",
    ]

    /// The graph relationship a kinship mention implies ("my sister" → .sibling),
    /// scanning each word since `role(forTerm:)` matches only bare terms.
    static func kinshipRole(for mention: String) -> RelationshipType? {
        if let role = RelationshipType.role(forTerm: mention) { return role }
        for word in mention.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" }) {
            if let role = RelationshipType.role(forTerm: String(word)) { return role }
        }
        return nil
    }

    static func isKinshipTerm(_ raw: String) -> Bool {
        let words = Set(raw.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "-" })
            .map(String.init))
        // Match the whole hyphenated term too (e.g. "mother-in-law").
        let joined = raw.lowercased().trimmingCharacters(in: .whitespaces)
        return kinshipWords.contains(joined) || !words.isDisjoint(with: kinshipWords)
    }

    /// Whether a kinship/relative term already resolves through the graph (e.g.
    /// "mom" when a parent edge to Me exists) — so it needn't be asked about.
    @MainActor
    static func graphResolves(_ mention: String, me: Person?, relationships: [PersonRelationship]) -> Bool {
        guard let me, let role = RelationshipType.role(forTerm: mention) else { return false }
        return personInRole(role, of: me, relationships: relationships) != nil
    }

    /// Mentions that need a "who is this?" question before saving: role references,
    /// bare kinship terms, and same-name ambiguity. Clear new names, already-known
    /// aliases, and graph-resolved relatives are left out (they resolve on their own).
    @MainActor
    static func mentionsNeedingConfirmation(_ mentions: [String], people: [Person], relationships: [PersonRelationship]) -> [String] {
        let me = people.first { $0.isMe }
        return mentions.compactMap { raw in
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isLikelyPerson(name) else { return nil }
            let matches = people.filter { $0.matches(name) }
            if matches.count > 1 { return name }
            if matches.count == 1 { return nil }
            if graphResolves(name, me: me, relationships: relationships) { return nil }
            if isRoleReference(name) || isKinshipTerm(name) { return name }
            return nil
        }
    }

    /// Self / generic references that aren't a specific person.
    private static let nonPersonExact: Set<String> = [
        "me", "myself", "self", "i", "we", "us", "everyone", "everybody",
        "team", "others", "people", "someone", "somebody", "no one", "nobody",
        "group", "family", "friends", "colleagues", "coworkers", "co-workers",
        "everybody else", "the team", "my team", "the group", "staff",
        // Third-person self-references the summarizer may use for the diary writer.
        "the writer", "the author", "the narrator", "writer", "author", "narrator"
    ]

    /// Plural group nouns — a mention ending in one of these is a group, not a person.
    private static let groupPluralWords: Set<String> = [
        "engineers", "developers", "managers", "members", "colleagues", "coworkers",
        "teammates", "peers", "leads", "directors", "analysts", "designers", "people",
        "folks", "others", "friends", "students", "residents", "doctors", "nurses",
        "customers", "clients", "users", "stakeholders", "partners", "employees",
        "guys", "everyone", "workers", "founders", "executives", "reports",
        // Family/social groups — a group of people, not one person.
        "kids", "children", "grandkids", "grandchildren", "parents", "grandparents",
        "cousins", "siblings", "relatives", "neighbors", "neighbours", "roommates",
        "twins", "guests", "boys", "girls", "everybody",
    ]

    /// A mention is a specific person, not a group/plural/self-reference.
    static func isLikelyPerson(_ raw: String) -> Bool {
        let name = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !nonPersonExact.contains(name) else { return false }

        let words = name.split(separator: " ").map(String.init)
        guard let last = words.last else { return false }
        if groupPluralWords.contains(last) { return false }
        // Multi-word phrase ending in a plural noun ("senior engineers", "team leads").
        if words.count >= 2, last.hasSuffix("s"), !last.hasSuffix("ss") {
            return false
        }
        return true
    }

    /// Finds the person who is `role` of `anchor` by walking edges, honoring
    /// symmetric types and the parent/child inverse.
    @MainActor
    private static func personInRole(_ role: RelationshipType, of anchor: Person,
                                     relationships: [PersonRelationship]) -> Person? {
        for edge in relationships {
            guard let subject = edge.subject, let object = edge.object else { continue }
            switch role {
            case .spouse, .sibling, .friend, .coworker:
                guard edge.type == role else { continue }
                if subject === anchor { return object }
                if object === anchor { return subject }
            case .parent:   // mentioned person is parent of anchor
                if edge.type == .parent, object === anchor { return subject }
                if edge.type == .child,  subject === anchor { return object }
            case .child:    // mentioned person is child of anchor
                if edge.type == .child,  object === anchor { return subject }
                if edge.type == .parent, subject === anchor { return object }
            case .other:
                continue
            }
        }
        return nil
    }
}
