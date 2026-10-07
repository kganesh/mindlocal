import Foundation

/// The five circles a person can belong to, for filtering the People tab.
///
/// Derived first, and only set by hand for the people derivation misses.
/// Relationships already record how someone is known, and asking the user to
/// tag every person a second time with the same information is a form to fill
/// in for no new knowledge. The hand-set list on `Person` exists because the
/// keyword fallback below is a closed vocabulary: a job title nobody thought of
/// leaves that person out of every filter, and only they can say where to put
/// them.
///
/// A person can be in more than one: a sister who works with you is family and
/// business both, and filtering by either should find her.
enum PersonCircle: String, CaseIterable, Identifiable {
    case family, business, health, social, spirituality

    var id: String { rawValue }

    var label: String {
        switch self {
        case .family:   "Family"
        case .business: "Business"
        case .health:   "Health"
        case .social:   "Social"
        case .spirituality: "Spirituality"
        }
    }

    var symbol: String {
        switch self {
        case .family:   "house"
        case .business: "briefcase"
        case .health:   "cross.case"
        case .social:   "figure.2"
        case .spirituality: "figure.mind.and.body"
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
        // No relationship type says anyone is a spiritual connection, and
        // inventing one would mean a case per profession. Reached by a word
        // below, or by the hand-set list on `Person`.
        case .spirituality: []
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
                         "recruiter", "business",
                         // Professional services. Matching is substring, so
                         // "legal" also catches "paralegal".
                         "attorney", "lawyer", "legal", "solicitor", "barrister",
                         "notary", "accountant", "auditor", "bookkeeper", "banker",
                         "broker", "financial", "insurance"]
        case .health:   ["doctor", "physician", "dentist", "nurse", "therapist",
                         "surgeon", "clinic", "hospital", "physio", "health",
                         "psychiatrist", "counsellor", "counselor"]
        case .social:   ["friend", "gym", "club", "neighbour", "neighbor", "school",
                         "college", "university", "social", "band", "team-mate",
                         "teammate"]
        case .spirituality: ["spiritual", "priest", "pastor", "minister", "reverend",
                             "chaplain", "bishop", "rabbi", "imam", "guru", "swami",
                             "monk", "nun", "pandit", "church", "temple", "mosque",
                             "synagogue", "gurdwara", "sangha", "congregation",
                             "meditation", "prayer"]
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

        // A circle the user set by hand ranks with a recorded relationship:
        // both are statements, where a word in a job title is a guess.
        found.formUnion(person.manualCircles)

        // Only consulted when nothing stated placed them, so a relationship or
        // a hand-set circle always beats a word that happens to appear in a job
        // title.
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
