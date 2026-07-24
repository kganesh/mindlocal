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
    /// The first name / primary label — what a diary mention usually says ("Sam").
    var name: String
    /// Optional last name, set lazily — only when needed to tell same-first-name
    /// people apart. Empty for most mentions. Additive; defaults keep records migrating.
    var lastName: String = ""
    /// Optional free-form context that distinguishes same-named people the way a
    /// diary does ("work", "gym", "cousin"). Shown in parentheses. Additive.
    var qualifier: String = ""
    /// Other ways this person is referred to (nicknames, relationship terms).
    var aliases: [String]
    /// The journaler themselves — the anchor for relative terms (wife/mom/…).
    var isMe: Bool
    var createdAt: Date

    @Relationship(inverse: \Experience.linkedPeople)
    var experiences: [Experience] = []
    /// Reminders about this person, e.g. "things to ask my doctor". Inverse of
    /// `Reminder.person` — lets services (not just views) read the open list
    /// directly, unlike `Conflict` which is only ever queried from a view.
    @Relationship(inverse: \Reminder.person)
    var reminders: [Reminder] = []

    init(id: UUID = UUID(), name: String, lastName: String = "", qualifier: String = "", aliases: [String] = [], isMe: Bool = false, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.lastName = lastName
        self.qualifier = qualifier
        self.aliases = aliases
        self.isMe = isMe
        self.createdAt = createdAt
    }

    /// Every label this person answers to, normalized for matching. Includes the
    /// full "first last" form so a mention that spells out the surname resolves.
    var normalizedNames: [String] {
        var forms = [name] + aliases
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.isEmpty { forms.append("\(name) \(last)") }
        return forms
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func matches(_ query: String) -> Bool {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return !q.isEmpty && normalizedNames.contains(q)
    }

    // MARK: - Display (progressive disclosure)

    /// The short distinguisher used when a bare first name is ambiguous: the last
    /// name if set, otherwise the context qualifier in parentheses. Empty if neither.
    var distinguisher: String {
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.isEmpty { return last }
        let q = qualifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? "" : "(\(q))"
    }

    /// First name plus distinguisher when one exists ("Sam Peterson", "Sam (work)");
    /// the bare name otherwise.
    var fullDisplayName: String {
        distinguisher.isEmpty ? name : "\(name) \(distinguisher)"
    }

    /// Progressive display: the bare first name unless another person shares it,
    /// in which case the distinguisher is appended so the two can be told apart.
    func displayName(among people: [Person]) -> String {
        let ambiguous = people.contains {
            $0 !== self && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
        return ambiguous ? fullDisplayName : name
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
    case spouse, parent, child, sibling
    case grandparent, grandchild
    case auntUncle, nieceNephew
    case cousin
    case parentInLaw, childInLaw, siblingInLaw
    case friend, coworker, physician, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .spouse:       "Spouse"
        case .parent:       "Parent"
        case .child:        "Child"
        case .sibling:      "Sibling"
        case .grandparent:  "Grandparent"
        case .grandchild:   "Grandchild"
        case .auntUncle:    "Aunt / Uncle"
        case .nieceNephew:  "Niece / Nephew"
        case .cousin:       "Cousin"
        case .parentInLaw:  "Parent-in-law"
        case .childInLaw:   "Child-in-law"
        case .siblingInLaw: "Sibling-in-law"
        case .friend:       "Friend"
        case .coworker:     "Coworker"
        case .physician:    "Physician"
        case .other:        "Related"
        }
    }

    /// Label from the object's side of the edge — the inverse of `label`. Symmetric
    /// types read the same from both sides.
    var inverseLabel: String {
        switch self {
        case .parent:       "Child"
        case .child:        "Parent"
        case .grandparent:  "Grandchild"
        case .grandchild:   "Grandparent"
        case .auntUncle:    "Niece / Nephew"
        case .nieceNephew:  "Aunt / Uncle"
        case .parentInLaw:  "Child-in-law"
        case .childInLaw:   "Parent-in-law"
        case .physician:    "Patient"
        default:            label
        }
    }

    var isSymmetric: Bool {
        switch self {
        case .spouse, .sibling, .cousin, .siblingInLaw, .friend, .coworker: true
        case .parent, .child, .grandparent, .grandchild, .auntUncle, .nieceNephew,
             .parentInLaw, .childInLaw, .physician, .other: false
        }
    }

    /// Spoken relationship words → the mentioned person's role relative to "me".
    static func role(forTerm term: String) -> RelationshipType? {
        let cleaned = term.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Normalise in-law phrasing so "mother in law" matches "mother-in-law".
        let t = cleaned.replacingOccurrences(of: " in law", with: "-in-law")
        switch t {
        case "wife", "husband", "spouse", "partner":                          return .spouse
        case "mom", "mother", "mum", "mommy", "dad", "father", "papa", "daddy": return .parent
        case "son", "daughter", "kid", "child", "little one", "little guy", "little girl":
            return .child
        case "sister", "brother", "sibling":                                  return .sibling
        case "grandma", "grandmother", "grandpa", "grandfather", "granddad",
             "grandad", "granny", "nana", "grandmom", "granddaddy", "grandparent":
            return .grandparent
        case "grandson", "granddaughter", "grandchild", "grandkid":           return .grandchild
        case "aunt", "auntie", "aunty", "uncle":                              return .auntUncle
        case "niece", "nephew":                                               return .nieceNephew
        case "cousin":                                                        return .cousin
        case "mother-in-law", "father-in-law", "parent-in-law", "mil", "fil": return .parentInLaw
        case "son-in-law", "daughter-in-law", "child-in-law":                 return .childInLaw
        case "brother-in-law", "sister-in-law", "sibling-in-law", "bil", "sil": return .siblingInLaw
        case "physician", "doctor", "doc", "gp":                              return .physician
        default: return nil
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
