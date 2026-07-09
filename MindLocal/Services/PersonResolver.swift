import Foundation
import SwiftData

/// Resolves raw people mentions (e.g. "Sam", "mom") to `Person` graph nodes,
/// matching by name/alias and creating a node for anyone new. Deterministic;
/// de-dupes within a batch. Interactive disambiguation of same-name people
/// (the "which Lilly?" case) and relationship edges come in the next phase.
enum PersonResolver {
    @MainActor
    static func resolve(_ mentions: [String], in context: ModelContext) -> [Person] {
        var pool = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        let relationships = (try? context.fetch(FetchDescriptor<PersonRelationship>())) ?? []
        let me = pool.first { $0.isMe }
        var result: [Person] = []

        func add(_ person: Person) {
            if !result.contains(where: { $0 === person }) { result.append(person) }
        }

        for raw in mentions {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            // 1. Direct name / alias match.
            if let match = pool.first(where: { $0.matches(name) }) {
                add(match)
                continue
            }
            // 2. Relative term via the graph ("mom" → parent-of-Me → Lilly).
            if let me, let role = RelationshipType.role(forTerm: name),
               let person = personInRole(role, of: me, relationships: relationships) {
                if !person.matches(name) { person.aliases.append(name) }  // remember for next time
                add(person)
                continue
            }
            // 3. New person.
            let person = Person(name: name)
            context.insert(person)
            pool.append(person)
            add(person)
        }
        return result
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
