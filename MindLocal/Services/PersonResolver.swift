import Foundation
import SwiftData

/// Resolves raw people mentions (e.g. "Sam", "mom") to `Person` graph nodes,
/// matching by name/alias and creating a node for anyone new. Deterministic;
/// de-dupes within a batch. Interactive disambiguation of same-name people
/// (the "which Lilly?" case) and relationship edges come in the next phase.
enum PersonResolver {
    @MainActor
    static func resolve(_ mentions: [String], in context: ModelContext) -> [Person] {
        let existing = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        var pool = existing
        var result: [Person] = []

        for raw in mentions {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            if let match = pool.first(where: { $0.matches(name) }) {
                if !result.contains(where: { $0 === match }) { result.append(match) }
            } else {
                let person = Person(name: name)
                context.insert(person)
                pool.append(person)
                result.append(person)
            }
        }
        return result
    }
}
