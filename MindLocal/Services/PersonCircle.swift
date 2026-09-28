import Foundation

/// The four circles a person can belong to, for filtering the People tab.
///
/// Derived rather than stored. Relationships already record how someone is
/// known, and asking the user to tag every person a second time with the same
/// information is a form to fill in for no new knowledge.
///
/// A person can be in more than one: a sister who works with you is family and
/// business both, and filtering by either should find her.
enum PersonCircle: String, CaseIterable, Identifiable {
    case family, business, health, social

    var id: String { rawValue }

    var label: String {
        switch self {
        case .family:   "Family"
        case .business: "Business"
        case .health:   "Health"
        case .social:   "Social"
        }
    }

    var symbol: String {
        switch self {
        case .family:   "house"
        case .business: "briefcase"
        case .health:   "cross.case"
        case .social:   "figure.2"
        }
    }

    /// The relationship types that place someone in this circle. `other` is in
    /// none of them: it means the edge exists but says nothing about which part
    /// of a life it belongs to.
    var relationshipTypes: Set<RelationshipType> {
        switch self {
        case .family:
            [.spouse, .parent, .child, .sibling, .grandparent, .grandchild,
             .auntUncle, .nieceNephew, .cousin, .parentInLaw, .childInLaw, .siblingInLaw]
        case .business: [.coworker]
        case .health:   [.physician]
        case .social:   [.friend]
        }
    }

    /// Words in a person's context note or occupation that place them here when
    /// no relationship has been recorded. Most people in a journal are written
    /// about long before anyone draws an edge to them, so without this the
    /// filters would find almost nobody.
    var keywords: [String] {
        switch self {
        case .family:   ["family", "mum", "mom", "dad", "wife", "husband", "son",
                         "daughter", "brother", "sister", "cousin", "aunt", "uncle",
                         "niece", "nephew", "grandma", "grandpa", "in-law"]
        case .business: ["work", "office", "colleague", "coworker", "boss", "manager",
                         "client", "team", "engineer", "developer", "consultant",
                         "recruiter", "business"]
        case .health:   ["doctor", "physician", "dentist", "nurse", "therapist",
                         "surgeon", "clinic", "hospital", "physio", "health",
                         "psychiatrist", "counsellor", "counselor"]
        case .social:   ["friend", "gym", "club", "neighbour", "neighbor", "school",
                         "college", "university", "social", "band", "team-mate",
                         "teammate"]
        }
    }
}

enum PersonCircleResolver {

    /// Every circle a person belongs to. Empty when nothing is recorded that
    /// would place them, which is a real answer: an unfiltered list still shows
    /// them, and a filtered one honestly does not.
    @MainActor
    static func circles(for person: Person,
                        relationships: [PersonRelationship]) -> Set<PersonCircle> {
        var found: Set<PersonCircle> = []

        let types = relationships
            .filter { $0.subject === person || $0.object === person }
            .map(\.type)
        for circle in PersonCircle.allCases where !circle.relationshipTypes.isDisjoint(with: types) {
            found.insert(circle)
        }

        // Only consulted when no edge placed them, so a recorded relationship
        // always beats a word that happens to appear in a job title.
        guard found.isEmpty else { return found }

        let text = ([person.qualifier, person.occupation] + person.aliases)
            .joined(separator: " ")
            .lowercased()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        for circle in PersonCircle.allCases
        where circle.keywords.contains(where: { text.contains($0) }) {
            found.insert(circle)
        }
        return found
    }
}
