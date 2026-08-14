import Foundation
import SwiftData

enum MemoryGraphBuilder {
    static func build(
        experiences: [Experience],
        events: [Event],
        decisions: [Decision],
        people: [Person],
        relationships: [PersonRelationship],
        conflicts: [Conflict],
        reminders: [Reminder]
    ) -> MemoryGraph {
        var graph = GraphAccumulator()

        for person in people {
            graph.addNode(MemoryNode(
                id: personNodeID(person),
                kind: .person,
                title: person.fullDisplayName,
                summary: person.aliases.isEmpty ? "" : "Also called: \(person.aliases.joined(separator: ", "))",
                date: person.createdAt,
                sourceID: person.id.uuidString,
                properties: [
                    "name": person.name,
                    "lastName": person.lastName,
                    "qualifier": person.qualifier,
                    "isMe": String(person.isMe)
                ]
            ))
        }

        for relationship in relationships {
            addRelationship(relationship, to: &graph)
        }

        for experience in experiences {
            addExperience(experience, people: people, to: &graph)
        }

        for event in events {
            addEvent(event, to: &graph)
        }

        for decision in decisions where decision.experience == nil {
            addDecision(decision, sourceEntryID: nil, to: &graph)
        }

        for reminder in reminders where reminder.experience == nil {
            addReminder(reminder, people: people, sourceEntryID: nil, to: &graph)
        }

        for conflict in conflicts where conflict.experience == nil {
            addConflict(conflict, people: people, sourceEntryID: nil, to: &graph)
        }

        return graph.makeGraph()
    }

    // MARK: - Source records

    private static func addExperience(_ experience: Experience, people: [Person], to graph: inout GraphAccumulator) {
        let entryID = entryNodeID(experience)
        graph.addNode(MemoryNode(
            id: entryID,
            kind: .entry,
            title: experience.title,
            summary: experience.summary,
            date: experience.timelineDate,
            sourceID: experience.id.uuidString,
            properties: [
                "entryKind": experience.kind.rawValue,
                "entryKindLabel": experience.kind.label,
                "tone": experience.tone.rawValue,
                "domain": experience.domain.rawValue,
                "rawText": experience.rawText ?? ""
            ]
        ))

        addDomain(experience.domain, owner: entryID, to: &graph)
        addTone(experience.tone, owner: entryID, to: &graph)

        if experience.hasLocation {
            addLocation(
                name: experience.location,
                latitude: experience.latitude,
                longitude: experience.longitude,
                owner: entryID,
                to: &graph
            )
        }

        for person in experience.linkedPeople {
            let personID = personNodeID(person)
            graph.addEdge(MemoryEdge(from: entryID, to: personID, kind: .mentions, label: "mentions"))
            graph.addEdge(MemoryEdge(from: personID, to: entryID, kind: .hasEntry, label: experience.kind.label))
        }

        // `experience.people` (raw extracted names) and `experience.linkedPeople`
        // (resolved at save time) are independent — a name here that was never
        // successfully linked (or whose link has gone stale) previously always
        // fell to an "unresolved" node, a permanently separate MemoryNodeID from
        // the real Person even once one exists with a matching name. That's
        // exactly what let a real, later-added Person's own connected evidence
        // (an argument entry, a conflict) become invisible to the boost that
        // comes from being connected to the person actually asked about. Same
        // self-healing fallback as addReminder/addConflict: re-check against
        // who's actually known now, since the graph rebuilds from scratch anyway.
        let linkedIDs = Set(experience.linkedPeople.map(personNodeID))
        for rawPerson in experience.people where !rawPerson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let match = people.first(where: { $0.matches(rawPerson) }) {
                let personID = personNodeID(match)
                guard !linkedIDs.contains(personID) else { continue }   // already connected above
                graph.addEdge(MemoryEdge(from: entryID, to: personID, kind: .mentions, label: "mentions"))
                graph.addEdge(MemoryEdge(from: personID, to: entryID, kind: .hasEntry, label: experience.kind.label))
            } else {
                let personID = unresolvedPersonNodeID(rawPerson)
                graph.addNode(MemoryNode(
                    id: personID,
                    kind: .person,
                    title: rawPerson,
                    summary: "Unresolved mention",
                    properties: ["resolved": "false"]
                ))
                graph.addEdge(MemoryEdge(from: entryID, to: personID, kind: .mentions, label: "unresolved mention"))
            }
        }

        for activity in experience.activities {
            addStringNode(activity, kind: .activity, prefix: "activity", owner: entryID, edgeKind: .hasActivity, to: &graph)
        }
        for outcome in experience.outcomes {
            addStringNode(outcome, kind: .outcome, prefix: "outcome", owner: entryID, edgeKind: .hasOutcome, to: &graph)
        }
        for hope in experience.hopes {
            addStringNode(hope, kind: .hope, prefix: "hope", owner: entryID, edgeKind: .hasHope, to: &graph)
        }

        for decision in experience.decisions {
            addDecision(decision, sourceEntryID: entryID, to: &graph)
        }
        for reminder in experience.reminders {
            addReminder(reminder, people: people, sourceEntryID: entryID, to: &graph)
        }
        for conflict in experience.conflicts {
            addConflict(conflict, people: people, sourceEntryID: entryID, to: &graph)
        }
    }

    private static func addEvent(_ event: Event, to graph: inout GraphAccumulator) {
        let eventID = eventNodeID(event)
        graph.addNode(MemoryNode(
            id: eventID,
            kind: .event,
            title: event.title,
            summary: event.notes,
            date: event.date,
            sourceID: event.id.uuidString,
            properties: [
                "domain": event.domain.rawValue,
                "isOutdoor": String(event.isOutdoor),
                "location": event.location
            ]
        ))
        addDomain(event.domain, owner: eventID, to: &graph)

        if !event.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addLocation(
                name: event.location,
                latitude: event.latitude,
                longitude: event.longitude,
                owner: eventID,
                to: &graph
            )
        }
        if let person = event.person {
            let personID = personNodeID(person)
            graph.addEdge(MemoryEdge(from: eventID, to: personID, kind: .mentions, label: "with"))
            graph.addEdge(MemoryEdge(from: personID, to: eventID, kind: .hasEvent, label: "event"))
        }
    }

    private static func addRelationship(_ relationship: PersonRelationship, to graph: inout GraphAccumulator) {
        guard let subject = relationship.subject, let object = relationship.object else { return }
        let relationshipID = MemoryNodeID(rawValue: "relationship:\(relationship.id.uuidString)")
        graph.addNode(MemoryNode(
            id: relationshipID,
            kind: .relationship,
            title: relationship.type.label,
            date: relationship.createdAt,
            sourceID: relationship.id.uuidString,
            properties: ["type": relationship.type.rawValue]
        ))
        let subjectID = personNodeID(subject)
        let objectID = personNodeID(object)
        graph.addEdge(MemoryEdge(from: subjectID, to: objectID, kind: .relatedTo, label: relationship.type.label))
        graph.addEdge(MemoryEdge(from: objectID, to: subjectID, kind: .relatedTo, label: relationship.type.inverseLabel))
        graph.addEdge(MemoryEdge(from: relationshipID, to: subjectID, kind: .mentions, label: "subject"))
        graph.addEdge(MemoryEdge(from: relationshipID, to: objectID, kind: .mentions, label: "object"))
    }

    private static func addDecision(_ decision: Decision, sourceEntryID: MemoryNodeID?, to graph: inout GraphAccumulator) {
        let decisionID = decisionNodeID(decision)
        graph.addNode(MemoryNode(
            id: decisionID,
            kind: .decision,
            title: decision.title,
            summary: decision.statement.isEmpty ? decision.rationale : decision.statement,
            date: decision.timelineDate,
            sourceID: decision.id.uuidString,
            properties: [
                "domain": decision.domain.rawValue,
                "stakes": decision.stakes.rawValue,
                "rationale": decision.rationale,
                "valuesPrioritized": decision.valuesPrioritized.joined(separator: ", "),
                "valuesTradedOff": decision.valuesTradedOff.joined(separator: ", ")
            ]
        ))
        addDomain(decision.domain, owner: decisionID, to: &graph)
        if let sourceEntryID {
            graph.addEdge(MemoryEdge(from: sourceEntryID, to: decisionID, kind: .hasDecision, label: "decision"))
            graph.addEdge(MemoryEdge(from: decisionID, to: sourceEntryID, kind: .sourceExperience, label: "from entry"))
        }
        if let outcome = decision.outcome {
            addStringNode(
                outcome.result.label,
                kind: .outcome,
                prefix: "decision-outcome",
                owner: decisionID,
                edgeKind: .hasOutcome,
                properties: ["notes": outcome.notes, "recordedAt": outcome.recordedAt.ISO8601Format()],
                to: &graph
            )
        }
    }

    private static func addReminder(_ reminder: Reminder, people: [Person], sourceEntryID: MemoryNodeID?, to graph: inout GraphAccumulator) {
        let reminderID = reminderNodeID(reminder)
        graph.addNode(MemoryNode(
            id: reminderID,
            kind: .reminder,
            title: reminder.text,
            date: reminder.createdAt,
            sourceID: reminder.id.uuidString,
            properties: [
                "isDone": String(reminder.isDone),
                "personName": reminder.personName
            ]
        ))
        if let sourceEntryID {
            graph.addEdge(MemoryEdge(from: sourceEntryID, to: reminderID, kind: .hasReminder, label: "reminder"))
        }
        // Falls back to a fresh name/alias match against the current People
        // list when `reminder.person` was never set (or has gone stale) —
        // the graph is rebuilt from scratch every time anyway, so re-checking
        // against who's actually known now self-heals a link that a one-time
        // resolve() at save time either missed or can no longer see.
        if let person = reminder.person ?? people.first(where: { $0.matches(reminder.personName) }) {
            let personID = personNodeID(person)
            graph.addEdge(MemoryEdge(from: reminderID, to: personID, kind: .aboutPerson, label: "about"))
            graph.addEdge(MemoryEdge(from: personID, to: reminderID, kind: .hasReminder, label: "reminder"))
        } else if !reminder.personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let personID = unresolvedPersonNodeID(reminder.personName)
            graph.addNode(MemoryNode(id: personID, kind: .person, title: reminder.personName, summary: "Unresolved reminder person"))
            graph.addEdge(MemoryEdge(from: reminderID, to: personID, kind: .aboutPerson, label: "unresolved"))
        }
    }

    private static func addConflict(_ conflict: Conflict, people: [Person], sourceEntryID: MemoryNodeID?, to graph: inout GraphAccumulator) {
        let conflictID = conflictNodeID(conflict)
        graph.addNode(MemoryNode(
            id: conflictID,
            kind: .conflict,
            title: conflict.summary.isEmpty ? "Disagreement" : conflict.summary,
            summary: conflict.feelings,
            date: conflict.createdAt,
            sourceID: conflict.id.uuidString,
            properties: [
                "resolution": conflict.resolution.rawValue,
                "personName": conflict.personName
            ]
        ))
        if let sourceEntryID {
            graph.addEdge(MemoryEdge(from: sourceEntryID, to: conflictID, kind: .hasConflict, label: "conflict"))
        }
        // Same self-healing fallback as addReminder above — a conflict whose
        // `withPerson` was never resolved (e.g. captured before this feature
        // existed, or before the person was formally added to People)
        // otherwise attaches to a permanently-orphaned "unresolved" node,
        // invisible to the boost that comes from being connected to the
        // person actually asked about — silently dropping real evidence for
        // "how do I resolve this conflict with X" out of the advisor's reach.
        if let person = conflict.withPerson ?? people.first(where: { $0.matches(conflict.personName) }) {
            let personID = personNodeID(person)
            graph.addEdge(MemoryEdge(from: conflictID, to: personID, kind: .withPerson, label: "with"))
            graph.addEdge(MemoryEdge(from: personID, to: conflictID, kind: .hasConflict, label: "conflict"))
        } else if !conflict.personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let personID = unresolvedPersonNodeID(conflict.personName)
            graph.addNode(MemoryNode(id: personID, kind: .person, title: conflict.personName, summary: "Unresolved conflict person"))
            graph.addEdge(MemoryEdge(from: conflictID, to: personID, kind: .withPerson, label: "unresolved"))
        }
    }

    // MARK: - Derived nodes

    private static func addDomain(_ domain: Domain, owner: MemoryNodeID, to graph: inout GraphAccumulator) {
        let nodeID = MemoryNodeID(rawValue: "domain:\(domain.rawValue)")
        graph.addNode(MemoryNode(id: nodeID, kind: .domain, title: domain.label, properties: ["rawValue": domain.rawValue]))
        graph.addEdge(MemoryEdge(from: owner, to: nodeID, kind: .inDomain, label: domain.label))
    }

    private static func addTone(_ tone: ExperienceTone, owner: MemoryNodeID, to graph: inout GraphAccumulator) {
        let nodeID = MemoryNodeID(rawValue: "tone:\(tone.rawValue)")
        graph.addNode(MemoryNode(id: nodeID, kind: .tone, title: tone.label, properties: ["rawValue": tone.rawValue]))
        graph.addEdge(MemoryEdge(from: owner, to: nodeID, kind: .hasTone, label: tone.label))
    }

    private static func addLocation(
        name: String,
        latitude: Double?,
        longitude: Double?,
        owner: MemoryNodeID,
        to graph: inout GraphAccumulator
    ) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let nodeID = MemoryNodeID(rawValue: "location:\(slug(cleaned))")
        graph.addNode(MemoryNode(
            id: nodeID,
            kind: .location,
            title: cleaned,
            properties: [
                "latitude": latitude.map { String($0) } ?? "",
                "longitude": longitude.map { String($0) } ?? ""
            ]
        ))
        graph.addEdge(MemoryEdge(from: owner, to: nodeID, kind: .happenedAt, label: cleaned))
    }

    private static func addStringNode(
        _ text: String,
        kind: MemoryNodeKind,
        prefix: String,
        owner: MemoryNodeID,
        edgeKind: MemoryEdgeKind,
        properties: [String: String] = [:],
        to graph: inout GraphAccumulator
    ) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let nodeID = MemoryNodeID(rawValue: "\(prefix):\(slug(cleaned))")
        graph.addNode(MemoryNode(id: nodeID, kind: kind, title: cleaned, properties: properties))
        graph.addEdge(MemoryEdge(from: owner, to: nodeID, kind: edgeKind, label: cleaned))
    }

    // MARK: - IDs

    static func personNodeID(_ person: Person) -> MemoryNodeID {
        MemoryNodeID(rawValue: "person:\(person.id.uuidString)")
    }

    static func entryNodeID(_ experience: Experience) -> MemoryNodeID {
        MemoryNodeID(rawValue: "entry:\(experience.id.uuidString)")
    }

    static func eventNodeID(_ event: Event) -> MemoryNodeID {
        MemoryNodeID(rawValue: "event:\(event.id.uuidString)")
    }

    private static func decisionNodeID(_ decision: Decision) -> MemoryNodeID {
        MemoryNodeID(rawValue: "decision:\(decision.id.uuidString)")
    }

    private static func reminderNodeID(_ reminder: Reminder) -> MemoryNodeID {
        MemoryNodeID(rawValue: "reminder:\(reminder.id.uuidString)")
    }

    private static func conflictNodeID(_ conflict: Conflict) -> MemoryNodeID {
        MemoryNodeID(rawValue: "conflict:\(conflict.id.uuidString)")
    }

    private static func unresolvedPersonNodeID(_ name: String) -> MemoryNodeID {
        MemoryNodeID(rawValue: "person-unresolved:\(slug(name))")
    }

    private static func slug(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let pieces = text
            .lowercased()
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        return String(pieces)
            .split(separator: "-")
            .joined(separator: "-")
    }
}

/// Rebuilds and persists the derived memory graph snapshot on device.
enum MemoryGraphStore {
    @MainActor
    @discardableResult
    static func rebuildAndPersist(in context: ModelContext) -> MemoryGraph {
        let experiences = fetch(Experience.self, in: context)
        let events = fetch(Event.self, in: context)
        let decisions = fetch(Decision.self, in: context)
        let people = fetch(Person.self, in: context)
        let relationships = fetch(PersonRelationship.self, in: context)
        let conflicts = fetch(Conflict.self, in: context)
        let reminders = fetch(Reminder.self, in: context)

        let graph = MemoryGraphBuilder.build(
            experiences: experiences,
            events: events,
            decisions: decisions,
            people: people,
            relationships: relationships,
            conflicts: conflicts,
            reminders: reminders
        )

        let snapshots = fetch(MemoryGraphSnapshot.self, in: context)
        let snapshot = snapshots.first ?? MemoryGraphSnapshot(graph: graph)
        snapshot.graph = graph
        if snapshots.isEmpty { context.insert(snapshot) }
        try? context.save()
        return graph
    }

    @MainActor
    static func latest(in context: ModelContext) -> MemoryGraph? {
        fetch(MemoryGraphSnapshot.self, in: context)
            .sorted { $0.builtAt > $1.builtAt }
            .first?
            .graph
    }

    @MainActor
    private static func fetch<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }
}

private struct GraphAccumulator {
    private(set) var nodesByID: [MemoryNodeID: MemoryNode] = [:]
    private(set) var edgesByID: [String: MemoryEdge] = [:]

    mutating func addNode(_ node: MemoryNode) {
        nodesByID[node.id] = node
    }

    mutating func addEdge(_ edge: MemoryEdge) {
        edgesByID[edge.id] = edge
    }

    func makeGraph() -> MemoryGraph {
        let nodes = nodesByID.values.sorted { $0.id.rawValue < $1.id.rawValue }
        let edges = edgesByID.values.sorted { $0.id < $1.id }
        return MemoryGraph(
            builtAt: .now,
            nodes: nodes,
            edges: edges,
            sourceFingerprint: fingerprint(nodes: nodes, edges: edges)
        )
    }

    private func fingerprint(nodes: [MemoryNode], edges: [MemoryEdge]) -> String {
        var hasher = Hasher()
        for node in nodes {
            hasher.combine(node.id)
            hasher.combine(node.title)
            hasher.combine(node.date)
        }
        for edge in edges {
            hasher.combine(edge.id)
        }
        return String(hasher.finalize())
    }
}
