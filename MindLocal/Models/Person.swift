import Foundation
import SwiftData

/// A person the user mentions in their journal — a node in the (eventual) people
/// graph. Mentions in entries resolve to a `Person` by name or alias, so
/// filtering by person works no matter how they were written ("mom", "Lilly").
///
/// Graph-ready: relationship edges between people (spouse/parent/…) and a "Me"
/// anchor come next; `isMe` and `RelationshipType` are defined now so they slot
/// in without reworking the schema.
@Model
final class Person {
    var id: UUID
    var name: String
    /// Other ways this person is referred to (nicknames, relationship terms).
    var aliases: [String]
    /// The journaler themselves — the anchor for relative terms (wife/mom/…).
    var isMe: Bool
    var createdAt: Date

    @Relationship(inverse: \Experience.linkedPeople)
    var experiences: [Experience] = []

    init(id: UUID = UUID(), name: String, aliases: [String] = [], isMe: Bool = false, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.isMe = isMe
        self.createdAt = createdAt
    }

    /// Every label this person answers to, normalized for matching.
    var normalizedNames: [String] {
        ([name] + aliases)
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func matches(_ query: String) -> Bool {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return !q.isEmpty && normalizedNames.contains(q)
    }
}

/// Typed edges for the people graph (used when relationship edges land next).
enum RelationshipType: String, Codable, CaseIterable {
    case spouse, parent, child, sibling, friend, coworker, other
}
