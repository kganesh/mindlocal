import Foundation
import SwiftData

/// Folds a duplicate `Person` into another (the survivor). Duplicates happen when
/// the same person is written two ways — a voice-entry typo ("Akhil" vs a
/// misheard spelling) resolves to two nodes. Merging moves the duplicate's entries
/// and relationship edges onto the survivor, keeps the duplicate's names as aliases
/// so future mentions auto-resolve, then deletes the duplicate.
enum PersonMerger {
    /// Merges `source` into `survivor`. After this, `source` is deleted and every
    /// entry/edge that pointed at it points at `survivor`. No-op if they're the
    /// same node. Merging a `Me` node preserves the `isMe` anchor on the survivor.
    @MainActor
    static func merge(_ source: Person, into survivor: Person, in context: ModelContext) {
        guard source !== survivor else { return }

        // Snapshot before mutating — reassigning `linkedPeople` mutates the inverse
        // `source.experiences` we'd otherwise be iterating.
        let sourceExperiences = source.experiences
        let sourceNames = [source.name] + source.aliases

        // 1. Move entries onto the survivor.
        for exp in sourceExperiences {
            if !exp.linkedPeople.contains(where: { $0 === survivor }) {
                exp.linkedPeople.append(survivor)
            }
            exp.linkedPeople.removeAll { $0 === source }
        }

        // 2. Keep the duplicate's names as aliases so past mentions still resolve
        //    to the survivor going forward.
        for label in sourceNames where !survivor.matches(label) {
            survivor.aliases.append(label)
        }

        // 3. Repoint relationship edges, then drop self-edges and duplicates the
        //    repointing may have created.
        let edges = (try? context.fetch(FetchDescriptor<PersonRelationship>())) ?? []
        for edge in edges {
            if edge.subject === source { edge.subject = survivor }
            if edge.object === source { edge.object = survivor }
        }
        pruneRedundantEdges(edges, in: context)

        // 4. Repoint conflicts recorded with the duplicate onto the survivor.
        let conflicts = (try? context.fetch(FetchDescriptor<Conflict>())) ?? []
        for conflict in conflicts where conflict.withPerson === source {
            conflict.withPerson = survivor
        }

        // 5. Repoint reminders and scheduled events. Both hold an optional
        //    `Person`, so deleting the duplicate would nullify them rather than
        //    fail — the reminder survives in the store but disappears from every
        //    screen that reads it off a person. Reminders are snapshotted first
        //    because reassigning `person` mutates the inverse being iterated.
        for reminder in Array(source.reminders) {
            reminder.person = survivor
        }
        let events = (try? context.fetch(FetchDescriptor<Event>())) ?? []
        for event in events where event.person === source {
            event.person = survivor
        }

        // 6. Carry over profile facts the survivor doesn't have. Which node
        //    survives is a UI choice, and the richer profile is often the one
        //    being folded in — a freshly created duplicate is the survivor when
        //    the correction is made on the new node. Nothing already recorded on
        //    the survivor is overwritten.
        if survivor.lastName.isEmpty { survivor.lastName = source.lastName }
        if survivor.qualifier.isEmpty { survivor.qualifier = source.qualifier }
        if survivor.occupation.isEmpty { survivor.occupation = source.occupation }
        if survivor.birthdate == nil { survivor.birthdate = source.birthdate }
        survivor.likes = mergedItems(survivor.likes, source.likes)
        survivor.dislikes = mergedItems(survivor.dislikes, source.dislikes)

        // 7. The survivor becomes the "Me" anchor if either side was.
        if source.isMe { survivor.isMe = true }

        context.delete(source)
    }

    /// Appends the duplicate's entries after the survivor's, dropping anything
    /// already recorded. Both lists are newest-first, so the survivor's own
    /// preferences stay at the top.
    private static func mergedItems(_ existing: [String], _ incoming: [String]) -> [String] {
        var result = existing
        for item in incoming
        where !result.contains(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) {
            result.append(item)
        }
        return result
    }

    /// Removes self-referential edges (subject === object) and duplicate edges of
    /// the same type between the same pair, keeping the earliest of each.
    @MainActor
    private static func pruneRedundantEdges(_ edges: [PersonRelationship], in context: ModelContext) {
        var kept: [(type: RelationshipType, a: Person, b: Person)] = []
        for edge in edges.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard let subject = edge.subject, let object = edge.object else { continue }
            if subject === object {
                context.delete(edge)
                continue
            }
            let duplicate = kept.contains { k in
                k.type == edge.type &&
                ((k.a === subject && k.b === object) || (k.a === object && k.b === subject))
            }
            if duplicate {
                context.delete(edge)
            } else {
                kept.append((edge.type, subject, object))
            }
        }
    }
}
