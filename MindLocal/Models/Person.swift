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

extension Person {
    /// The journaler node — anchor for relative terms. Created on demand.
    @MainActor
    static func fetchOrCreateMe(in context: ModelContext) -> Person {
        let all = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        if let me = all.first(where: { $0.isMe }) { return me }
        let me = Person(name: "Me", isMe: true)
        context.insert(me)
        return me
    }
}

/// Typed edges for the people graph. A `PersonRelationship` reads
/// "subject is <type> of object" (e.g. Lilly is `spouse` of Me; Lilly is
/// `parent` of Emma). spouse/sibling/friend/coworker are symmetric; parent/child
/// are inverses of each other.
enum RelationshipType: String, Codable, CaseIterable, Identifiable {
    case spouse, parent, child, sibling, friend, coworker, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .spouse:   "Spouse"
        case .parent:   "Parent"
        case .child:    "Child"
        case .sibling:  "Sibling"
        case .friend:   "Friend"
        case .coworker: "Coworker"
        case .other:    "Related"
        }
    }

    var isSymmetric: Bool {
        switch self {
        case .spouse, .sibling, .friend, .coworker: true
        case .parent, .child, .other: false
        }
    }

    /// Spoken relationship words → the mentioned person's role relative to "me".
    static func role(forTerm term: String) -> RelationshipType? {
        switch term.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "wife", "husband", "spouse", "partner":                 .spouse
        case "mom", "mother", "mum", "mommy", "dad", "father", "papa", "daddy": .parent
        case "son", "daughter", "kid", "child":                      .child
        case "sister", "brother", "sibling":                         .sibling
        default: nil
        }
    }
}

@Model
final class PersonRelationship {
    var id: UUID
    var typeRaw: String
    @Relationship var subject: Person?
    @Relationship var object: Person?
    var createdAt: Date

    var type: RelationshipType {
        get { RelationshipType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    init(subject: Person?, type: RelationshipType, object: Person?, id: UUID = UUID(), createdAt: Date = .now) {
        self.id = id
        self.subject = subject
        self.typeRaw = type.rawValue
        self.object = object
        self.createdAt = createdAt
    }
}
