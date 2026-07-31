import Foundation

struct MemoryResolvedPerson: Identifiable, Hashable {
    var id: UUID { personID }
    let personID: UUID
    let nodeID: MemoryNodeID
    let displayName: String
    let matchedPhrase: String
    let matchKind: MatchKind

    enum MatchKind: String {
        case name
        case alias
        case relationship
    }
}

struct MemoryQueryIntent {
    var query: String
    var mentionedPeople: [MemoryResolvedPerson]
    var timeRange: DateInterval?
    var domains: [Domain]
    var tones: [ExperienceTone]
    var entryKinds: [ExperienceKind]
    var wantsReminders: Bool
    var wantsConflicts: Bool
    var wantsDecisions: Bool
    var wantsEvents: Bool
    /// "who is X and when did I last see them" — a small on-device model is
    /// unreliable at scanning several dated entries and picking the true
    /// maximum itself, so this flag routes to a deterministic computation
    /// (`MemoryGraphRetriever`'s `mostRecentInteraction`) instead of asking
    /// the model to reason it out from raw context text.
    var wantsMostRecentInteraction: Bool

    static func empty(query: String) -> MemoryQueryIntent {
        MemoryQueryIntent(
            query: query,
            mentionedPeople: [],
            timeRange: nil,
            domains: [],
            tones: [],
            entryKinds: [],
            wantsReminders: false,
            wantsConflicts: false,
            wantsDecisions: false,
            wantsEvents: false,
            wantsMostRecentInteraction: false
        )
    }
}

struct MemoryGraphRetrievalResult {
    var intent: MemoryQueryIntent
    var seedNodes: [MemoryNode]
    var expandedNodes: [MemoryNode]
    var edges: [MemoryEdge]
    /// The single most recent entry/event/decision/reminder/conflict directly
    /// linked to the question's (first) resolved person, computed as a real
    /// max-by-date over ALL of that person's connected evidence — not just
    /// whatever made it into the score-ranked, capped `expandedNodes`. Set
    /// only when `intent.wantsMostRecentInteraction` and a person resolved.
    var mostRecentInteraction: (person: MemoryResolvedPerson, node: MemoryNode)? = nil

    static func evidenceKind(_ kind: MemoryNodeKind) -> Bool {
        switch kind {
        case .entry, .event, .decision, .reminder, .conflict:
            true
        default:
            false
        }
    }

    var evidenceNodes: [MemoryNode] {
        expandedNodes.filter { Self.evidenceKind($0.kind) }
    }
}

enum MemoryQueryResolver {
    static func resolve(
        query: String,
        people: [Person],
        relationships: [PersonRelationship],
        now: Date = .now
    ) -> MemoryQueryIntent {
        let normalized = query.lowercased()
        var intent = MemoryQueryIntent.empty(query: query)
        intent.mentionedPeople = resolvePeople(in: query, people: people, relationships: relationships)
        intent.domains = Domain.allCases.filter { containsTerm($0.rawValue, in: normalized) || containsTerm($0.label, in: normalized) }
        intent.tones = ExperienceTone.allCases.filter { containsTerm($0.rawValue, in: normalized) || containsTerm($0.label, in: normalized) }
        intent.entryKinds = ExperienceKind.allCases.filter {
            containsTerm($0.rawValue, in: normalized)
                || containsTerm($0.label, in: normalized)
                || ($0 == .dailyLog && containsTerm("journal", in: normalized))
                || ($0 == .dailyLog && containsTerm("diary", in: normalized))
        }
        intent.timeRange = resolveTimeRange(in: normalized, now: now)
        intent.wantsReminders = ["reminder", "remember", "follow up", "ask", "bring up"].contains { containsTerm($0, in: normalized) }
        intent.wantsConflicts = ["conflict", "argument", "fight", "tension", "disagreement"].contains { containsTerm($0, in: normalized) }
        intent.wantsDecisions = ["decision", "decide", "decided", "choice", "regret"].contains { containsTerm($0, in: normalized) }
        intent.wantsEvents = ["event", "meeting", "appointment", "calendar", "seeing", "before"].contains { containsTerm($0, in: normalized) }
        intent.wantsMostRecentInteraction = [
            "last time", "last met", "last saw", "last spoke", "last talked",
            "last meet", "last see", "most recently", "when did i last"
        ].contains { containsTerm($0, in: normalized) }
        return intent
    }

    private static func resolvePeople(
        in query: String,
        people: [Person],
        relationships: [PersonRelationship]
    ) -> [MemoryResolvedPerson] {
        let normalized = query.lowercased()
        var resolved: [MemoryResolvedPerson] = []
        var seen = Set<UUID>()

        func add(_ person: Person, phrase: String, kind: MemoryResolvedPerson.MatchKind) {
            guard seen.insert(person.id).inserted else { return }
            resolved.append(MemoryResolvedPerson(
                personID: person.id,
                nodeID: MemoryGraphBuilder.personNodeID(person),
                displayName: person.fullDisplayName,
                matchedPhrase: phrase,
                matchKind: kind
            ))
        }

        let sortedPeople = people.sorted { $0.fullDisplayName.count > $1.fullDisplayName.count }
        for person in sortedPeople {
            for name in person.normalizedNames.sorted(by: { $0.count > $1.count }) {
                guard containsTerm(name, in: normalized) else { continue }
                let kind: MemoryResolvedPerson.MatchKind = person.name.lowercased() == name ? .name : .alias
                add(person, phrase: name, kind: kind)
                break
            }
        }

        guard let me = people.first(where: { $0.isMe }) else { return resolved }
        for phrase in relationshipPhrases(in: normalized) {
            let rolePhrase = phrase.strippingLeadingPossessive()
            guard let role = PersonResolver.kinshipRole(for: rolePhrase)
                    ?? RelationshipType.role(forTerm: rolePhrase),
                  let person = personInRole(role, of: me, relationships: relationships) else {
                continue
            }
            add(person, phrase: phrase, kind: .relationship)
        }

        return resolved
    }

    private static func relationshipPhrases(in normalized: String) -> [String] {
        let candidates = [
            "my wife", "my husband", "my spouse", "my partner",
            "my mom", "my mother", "my dad", "my father",
            "my son", "my daughter", "my child",
            "my sister", "my brother", "my sibling",
            "my manager", "my boss", "my doctor", "my physician",
            "wife", "husband", "spouse", "partner", "mom", "mother",
            "dad", "father", "son", "daughter", "sister", "brother",
            "manager", "boss", "doctor", "physician"
        ]
        return candidates.filter { containsTerm($0, in: normalized) }
    }

    private static func personInRole(
        _ role: RelationshipType,
        of anchor: Person,
        relationships: [PersonRelationship]
    ) -> Person? {
        for edge in relationships {
            guard let subject = edge.subject, let object = edge.object else { continue }
            switch role {
            case .spouse, .sibling, .cousin, .siblingInLaw, .friend, .coworker:
                guard edge.type == role else { continue }
                if subject === anchor { return object }
                if object === anchor { return subject }
            case .parent:
                if edge.type == .parent, object === anchor { return subject }
                if edge.type == .child, subject === anchor { return object }
            case .child:
                if edge.type == .child, object === anchor { return subject }
                if edge.type == .parent, subject === anchor { return object }
            case .grandparent:
                if edge.type == .grandparent, object === anchor { return subject }
                if edge.type == .grandchild, subject === anchor { return object }
            case .grandchild:
                if edge.type == .grandchild, object === anchor { return subject }
                if edge.type == .grandparent, subject === anchor { return object }
            case .auntUncle:
                if edge.type == .auntUncle, object === anchor { return subject }
                if edge.type == .nieceNephew, subject === anchor { return object }
            case .nieceNephew:
                if edge.type == .nieceNephew, object === anchor { return subject }
                if edge.type == .auntUncle, subject === anchor { return object }
            case .parentInLaw:
                if edge.type == .parentInLaw, object === anchor { return subject }
                if edge.type == .childInLaw, subject === anchor { return object }
            case .childInLaw:
                if edge.type == .childInLaw, object === anchor { return subject }
                if edge.type == .parentInLaw, subject === anchor { return object }
            case .physician:
                if edge.type == .physician, object === anchor { return subject }
            case .other:
                continue
            }
        }
        return nil
    }

    private static func resolveTimeRange(in normalized: String, now: Date) -> DateInterval? {
        let calendar = Calendar.current
        if containsTerm("today", in: normalized) {
            let start = calendar.startOfDay(for: now)
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start) ?? now)
        }
        if containsTerm("yesterday", in: normalized) {
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            return DateInterval(start: start, end: today)
        }
        if containsTerm("this week", in: normalized) {
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return DateInterval(start: start, end: now)
        }
        if containsTerm("recent", in: normalized) || containsTerm("recently", in: normalized) {
            let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return DateInterval(start: start, end: now)
        }
        return nil
    }

    static func containsTerm(_ term: String, in normalizedText: String) -> Bool {
        let normalizedTerm = term.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTerm.isEmpty else { return false }
        var searchStart = normalizedText.startIndex
        while let range = normalizedText.range(of: normalizedTerm, options: [], range: searchStart..<normalizedText.endIndex) {
            if isBoundaryBefore(range.lowerBound, in: normalizedText),
               isBoundaryAfter(range.upperBound, in: normalizedText) {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private static func isBoundaryBefore(_ index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return true }
        return !isWordCharacter(text[text.index(before: index)])
    }

    private static func isBoundaryAfter(_ index: String.Index, in text: String) -> Bool {
        guard index < text.endIndex else { return true }
        return !isWordCharacter(text[index])
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "'"
    }
}

enum MemoryGraphRetriever {
    static func retrieve(
        query: String,
        graph: MemoryGraph,
        people: [Person],
        relationships: [PersonRelationship],
        now: Date = .now,
        limit: Int = 24
    ) -> MemoryGraphRetrievalResult {
        let intent = MemoryQueryResolver.resolve(query: query, people: people, relationships: relationships, now: now)
        return retrieve(intent: intent, graph: graph, now: now, limit: limit)
    }

    static func retrieve(
        intent: MemoryQueryIntent,
        graph: MemoryGraph,
        now: Date = .now,
        limit: Int = 24
    ) -> MemoryGraphRetrievalResult {
        let index = GraphIndex(graph: graph)
        var ranked: [MemoryNodeID: Double] = [:]

        func boost(_ id: MemoryNodeID, by amount: Double) {
            ranked[id, default: 0] += amount
        }

        // Nodes actually connected to a mentioned person via a real graph edge —
        // used below to keep the structured-intent boost from applying to
        // unrelated nodes just because the question happened to contain a
        // matching keyword (e.g. "meeting" triggers wantsEvents, which would
        // otherwise boost every event in the whole graph, not just this
        // person's).
        var personConnectedIDs: Set<MemoryNodeID> = []

        for person in intent.mentionedPeople {
            boost(person.nodeID, by: 100)
            personConnectedIDs.insert(person.nodeID)
            for edge in index.edges(touching: person.nodeID) {
                let other = edge.from == person.nodeID ? edge.to : edge.from
                boost(other, by: neighborBoost(for: edge.kind))
                personConnectedIDs.insert(other)
            }
        }

        for node in graph.nodes {
            // A tone/domain/kind/time filter (matchesStructuredIntent) is a
            // graph-wide signal with no idea who a node is actually about — safe
            // when the question doesn't name anyone, but too broad once it does,
            // since it would otherwise let an unrelated node (no person, or a
            // different person entirely) outrank evidence genuinely linked to
            // the person asked about.
            let structuredIntentApplies = intent.mentionedPeople.isEmpty || personConnectedIDs.contains(node.id)
            if structuredIntentApplies, matchesStructuredIntent(node, intent: intent) {
                boost(node.id, by: 35)
            }
            if matchesText(node, query: intent.query) {
                boost(node.id, by: 12)
            }
            if isRecentEvidence(node, now: now) {
                boost(node.id, by: 4)
            }
        }

        let seedIDs = ranked
            .sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
            .prefix(max(limit / 2, 6))
            .map(\.key)

        var expandedScores = ranked
        var selectedEdges: [MemoryEdge] = []
        for id in seedIDs {
            for edge in index.edges(touching: id) {
                selectedEdges.append(edge)
                let other = edge.from == id ? edge.to : edge.from
                expandedScores[other, default: 0] += neighborBoost(for: edge.kind) / 2
            }
        }

        let expandedNodes = expandedScores
            .compactMap { id, score -> (MemoryNode, Double)? in
                guard let node = index.node(id) else { return nil }
                return (node, score + evidencePriority(node))
            }
            .sorted {
                if $0.1 == $1.1 {
                    return ($0.0.date ?? .distantPast) > ($1.0.date ?? .distantPast)
                }
                return $0.1 > $1.1
            }
            .prefix(limit)
            .map(\.0)

        let seedNodes = seedIDs.compactMap(index.node)
        let expandedIDs = Set(expandedNodes.map(\.id))
        let edges = selectedEdges
            .filter { expandedIDs.contains($0.from) || expandedIDs.contains($0.to) }
            .uniquedByID()

        return MemoryGraphRetrievalResult(
            intent: intent,
            seedNodes: seedNodes,
            expandedNodes: expandedNodes,
            edges: edges,
            mostRecentInteraction: mostRecentInteraction(for: intent, index: index)
        )
    }

    /// A real max-by-date over every entry/event/decision/reminder/conflict
    /// directly linked to the person, computed here in plain code instead of
    /// asking the on-device model to scan dated context text and find the
    /// maximum itself — a small model is unreliable at exactly that
    /// computation, which is why the app already resolves relative/absolute
    /// dates deterministically everywhere else (AppointmentDateResolver,
    /// ActivityTimeResolver) rather than trusting model-computed dates.
    private static func mostRecentInteraction(
        for intent: MemoryQueryIntent,
        index: GraphIndex
    ) -> (person: MemoryResolvedPerson, node: MemoryNode)? {
        guard intent.wantsMostRecentInteraction, let person = intent.mentionedPeople.first else { return nil }
        let connected = index.edges(touching: person.nodeID).compactMap { edge -> MemoryNode? in
            let otherID = edge.from == person.nodeID ? edge.to : edge.from
            return index.node(otherID)
        }
        let eligible = connected.filter { MemoryGraphRetrievalResult.evidenceKind($0.kind) }
        guard let mostRecent = eligible.max(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }) else {
            return nil
        }
        return (person, mostRecent)
    }

    private static func matchesStructuredIntent(_ node: MemoryNode, intent: MemoryQueryIntent) -> Bool {
        if let range = intent.timeRange, let date = node.date, !range.contains(date) { return false }
        if !intent.domains.isEmpty, !intent.domains.contains(where: { node.properties["domain"] == $0.rawValue || node.properties["rawValue"] == $0.rawValue }) {
            return false
        }
        if !intent.tones.isEmpty, !intent.tones.contains(where: { node.properties["tone"] == $0.rawValue || node.properties["rawValue"] == $0.rawValue }) {
            return false
        }
        if !intent.entryKinds.isEmpty, !intent.entryKinds.contains(where: { node.properties["entryKind"] == $0.rawValue }) {
            return false
        }
        if intent.wantsReminders, node.kind != .reminder { return false }
        if intent.wantsConflicts, node.kind != .conflict { return false }
        if intent.wantsDecisions, node.kind != .decision { return false }
        if intent.wantsEvents, node.kind != .event { return false }
        return intent.timeRange != nil
            || !intent.domains.isEmpty
            || !intent.tones.isEmpty
            || !intent.entryKinds.isEmpty
            || intent.wantsReminders
            || intent.wantsConflicts
            || intent.wantsDecisions
            || intent.wantsEvents
    }

    private static func matchesText(_ node: MemoryNode, query: String) -> Bool {
        let haystack = ([node.title, node.summary] + node.properties.values).joined(separator: " ").lowercased()
        let terms = query.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 4 }
        guard !terms.isEmpty else { return false }
        return terms.contains { MemoryQueryResolver.containsTerm($0, in: haystack) }
    }

    private static func neighborBoost(for edgeKind: MemoryEdgeKind) -> Double {
        switch edgeKind {
        case .hasReminder, .aboutPerson:
            28
        case .hasConflict, .withPerson:
            24
        case .hasEvent:
            22
        case .hasEntry, .mentions:
            20
        case .hasDecision:
            18
        case .relatedTo:
            14
        default:
            8
        }
    }

    private static func evidencePriority(_ node: MemoryNode) -> Double {
        switch node.kind {
        case .reminder:
            node.properties["isDone"] == "false" ? 20 : 6
        case .event:
            16
        case .entry:
            14
        case .conflict:
            12
        case .decision:
            10
        default:
            0
        }
    }

    private static func isRecentEvidence(_ node: MemoryNode, now: Date) -> Bool {
        guard let date = node.date else { return false }
        guard [.entry, .event, .decision, .reminder, .conflict].contains(node.kind) else { return false }
        return abs(date.timeIntervalSince(now)) <= 30 * 86_400
    }
}

private struct GraphIndex {
    private let nodesByID: [MemoryNodeID: MemoryNode]
    private let edgesByNodeID: [MemoryNodeID: [MemoryEdge]]

    init(graph: MemoryGraph) {
        self.nodesByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        var edges: [MemoryNodeID: [MemoryEdge]] = [:]
        for edge in graph.edges {
            edges[edge.from, default: []].append(edge)
            edges[edge.to, default: []].append(edge)
        }
        self.edgesByNodeID = edges
    }

    func node(_ id: MemoryNodeID) -> MemoryNode? {
        nodesByID[id]
    }

    func edges(touching id: MemoryNodeID) -> [MemoryEdge] {
        edgesByNodeID[id] ?? []
    }
}

private extension Array where Element == MemoryEdge {
    func uniquedByID() -> [MemoryEdge] {
        var seen = Set<String>()
        var result: [MemoryEdge] = []
        for edge in self where seen.insert(edge.id).inserted {
            result.append(edge)
        }
        return result
    }
}

private extension String {
    func strippingLeadingPossessive() -> String {
        let trimmed = lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("my ") ? String(trimmed.dropFirst(3)) : trimmed
    }
}
