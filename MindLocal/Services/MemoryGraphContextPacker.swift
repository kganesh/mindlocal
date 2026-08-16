import Foundation

/// Turns graph retrieval results into plain English for the advisor prompt.
///
/// This used to emit a terse machine notation — bracketed metadata
/// (`[entry, 2026-07-18] Title Summary (entryKind: experience, tone: pleasant)`)
/// plus a separate block of arrows (`Akhil's birthday --happenedAt--> 4545
/// Celia Ct`). Two problems with that. The model had to decode a syntax before
/// it could reason, and every fragment was an invitation to recombine pieces
/// that were never connected — which is exactly how a question about Nora came
/// back answered with Akhil's date.
///
/// So each node is now written as a finished sentence with its own facts folded
/// in. Doing that removes the need for the arrow block entirely: those edges
/// existed only because the node line could not say where something happened or
/// who was there.
///
/// Dates carry both the weekday and how long ago they were. Small on-device
/// models are poor at deciding whether 2026-08-02 falls in "last week"; being
/// told "13 days ago" removes the arithmetic.
enum MemoryGraphContextPacker {
    /// The context string plus a manifest of what went into it, so an answer
    /// can be checked against the evidence the model was actually shown.
    /// `evidenceTitles` is index-aligned with the numbered "Evidence:" lines —
    /// element 0 is line 1 — which is what the model cites by number.
    struct PackedContext: Equatable {
        var text: String
        var evidenceTitles: [String]
        var knownPeople: Set<String>
        var knownDates: Set<String>

        static let empty = PackedContext(text: "", evidenceTitles: [], knownPeople: [], knownDates: [])
    }

    static func pack(_ result: MemoryGraphRetrievalResult, maxNodes: Int = 10, now: Date = .now) -> String {
        packWithManifest(result, maxNodes: maxNodes, now: now).text
    }

    static func packWithManifest(_ result: MemoryGraphRetrievalResult,
                                 maxNodes: Int = 10,
                                 now: Date = .now) -> PackedContext {
        // `result.evidenceNodes`/`expandedNodes` already arrive ordered by the
        // retriever's relevance score. Keep that order — the layer above
        // truncates from the END of the string, so the most relevant evidence
        // has to sit closest to the front or a tight budget silently drops it.
        let evidence = Array(result.evidenceNodes.prefix(maxNodes))
        let evidenceIDs = Set(evidence.map(\.id))
        let relatedLimit = max(0, maxNodes - evidence.count)
        // Attribute nodes (hope / activity / outcome / tone / domain /
        // location) carry no date and no owner, so as standalone lines they
        // mislead. They still reach the model, folded into the sentence of the
        // record they belong to.
        let alreadyNamed = Set(result.intent.mentionedPeople.map(\.displayName))
        let related = Array(result.expandedNodes
            .filter { !evidenceIDs.contains($0.id) }
            .filter { MemoryGraphRetrievalResult.evidenceKind($0.kind)
                || ($0.kind == .person && !alreadyNamed.contains($0.title)) }
            .prefix(relatedLimit))

        let nodesByID: [MemoryNodeID: MemoryNode] = Dictionary(
            (result.seedNodes + result.expandedNodes).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let facts = attachedFacts(edges: result.edges, nodesByID: nodesByID)

        var blocks: [String] = []

        // Stated as a computed fact rather than left for the model to derive by
        // scanning dates, which it does unreliably.
        if let mostRecent = result.mostRecentInteraction {
            blocks.append(
                "Your most recent interaction with \(mostRecent.person.displayName) is "
                + "already worked out for you, and is correct: "
                + sentence(for: mostRecent.node, facts: facts, now: now)
                + " Use this date as given."
            )
        }

        if !result.intent.mentionedPeople.isEmpty {
            let names = result.intent.mentionedPeople.map(\.displayName)
            blocks.append("This question is about \(list(names)).")
        }

        if !evidence.isEmpty {
            let lines = evidence.enumerated().map { index, node in
                "\(index + 1). \(sentence(for: node, facts: facts, now: now))"
            }
            blocks.append("Evidence:\n" + lines.joined(separator: "\n"))
        }

        if !related.isEmpty {
            let lines = related.enumerated().map { index, node in
                "\(index + 1). \(sentence(for: node, facts: facts, now: now))"
            }
            blocks.append("Also connected:\n" + lines.joined(separator: "\n"))
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let shown = evidence + related
        var knownPeople = Set(result.intent.mentionedPeople.map(\.displayName))
        knownPeople.formUnion(shown.filter { $0.kind == .person }.map(\.title))
        knownPeople.formUnion(facts.values.flatMap(\.people))
        if let mostRecent = result.mostRecentInteraction {
            knownPeople.insert(mostRecent.person.displayName)
        }
        var knownDates = Set(shown.compactMap { $0.date.map(dateFormatter.string(from:)) })
        if let date = result.mostRecentInteraction?.node.date {
            knownDates.insert(dateFormatter.string(from: date))
        }

        return PackedContext(
            text: blocks.isEmpty ? "" : blocks.joined(separator: "\n\n"),
            evidenceTitles: evidence.map(\.title),
            knownPeople: knownPeople,
            knownDates: knownDates
        )
    }

    // MARK: - Facts attached to a node

    /// What the edges say about each node, gathered so a sentence can state it
    /// inline instead of the reader having to join an arrow diagram back up.
    private struct Facts {
        var people: [String] = []
        var location: String?
    }

    private static func attachedFacts(edges: [MemoryEdge],
                                      nodesByID: [MemoryNodeID: MemoryNode]) -> [MemoryNodeID: Facts] {
        var facts: [MemoryNodeID: Facts] = [:]
        for edge in edges {
            guard let from = nodesByID[edge.from], let to = nodesByID[edge.to] else { continue }
            switch edge.kind {
            case .mentions, .withPerson, .aboutPerson:
                // record -> person
                guard to.kind == .person, !to.title.isEmpty else { continue }
                if !facts[from.id, default: Facts()].people.contains(to.title) {
                    facts[from.id, default: Facts()].people.append(to.title)
                }
            case .hasEntry, .hasEvent, .hasReminder, .hasConflict, .hasDecision:
                // person -> record
                guard from.kind == .person, !from.title.isEmpty else { continue }
                if !facts[to.id, default: Facts()].people.contains(from.title) {
                    facts[to.id, default: Facts()].people.append(from.title)
                }
            case .happenedAt:
                guard !to.title.isEmpty else { continue }
                facts[from.id, default: Facts()].location = to.title
            default:
                continue
            }
        }
        return facts
    }

    // MARK: - Sentences

    private static func sentence(for node: MemoryNode,
                                 facts: [MemoryNodeID: Facts],
                                 now: Date) -> String {
        let fact = facts[node.id] ?? Facts()
        let when = node.date.map { "On \(longDate($0)) (\(relative($0, now: now))), " } ?? ""
        let people = fact.people.isEmpty ? "" : " It involved \(list(fact.people))."
        let place = fact.location.map { " It took place at \($0.replacingOccurrences(of: "\n", with: ", "))." } ?? ""
        let body = node.summary.isEmpty ? "" : " \(clip(node.summary))"

        switch node.kind {
        case .event:
            return "\(when)there was an event called “\(node.title)”.\(body)\(people)\(place)"

        case .entry:
            let kind = node.properties["entryKindLabel"].map { $0.lowercased() } ?? "note"
            var text = "\(when)you wrote \(article(for: kind)) \(kind) titled “\(node.title)”.\(body)"
            if let tone = node.properties["tone"], !tone.isEmpty {
                text += " You described it as \(tone)."
            }
            if let domain = node.properties["domain"], !domain.isEmpty, domain != "other" {
                text += " It was about \(domain)."
            }
            return text + people + place

        case .decision:
            return "\(when)you decided: \(node.title).\(body)\(people)"

        case .reminder:
            let done = node.properties["isDone"] == "true"
            let who = fact.people.isEmpty ? "" : " for when you next see \(list(fact.people))"
            return done
                ? "You had a reminder\(who): \(node.title). It is done."
                : "You have an open reminder\(who): \(node.title)."

        case .conflict:
            let who = fact.people.isEmpty ? "someone" : list(fact.people)
            return "\(when)you had a disagreement with \(who) about \(node.title).\(body)"

        case .person:
            return node.summary.isEmpty
                ? "\(node.title) is someone you know."
                : "\(node.title): \(clip(node.summary))"

        default:
            return "\(when)\(node.title).\(body)"
        }
    }

    // MARK: - Helpers

    private static func longDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM yyyy"
        return formatter.string(from: date)
    }

    /// "13 days ago" / "in 3 days" — so the model never has to work out whether
    /// a date falls inside the period the question asked about.
    private static func relative(_ date: Date, now: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0
        switch days {
        case 0:            return "today"
        case 1:            return "yesterday"
        case -1:           return "tomorrow"
        case 2...:         return "\(days) days ago"
        default:           return "in \(-days) days"
        }
    }

    private static func article(for word: String) -> String {
        guard let first = word.lowercased().first else { return "a" }
        return "aeiou".contains(first) ? "an" : "a"
    }

    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0:  return ""
        case 1:  return items[0]
        case 2:  return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and " + items[items.count - 1]
        }
    }

    private static func clip(_ text: String, max: Int = 180) -> String {
        let single = text.replacingOccurrences(of: "\n", with: " ")
        return single.count <= max ? single : String(single.prefix(max)) + "…"
    }
}
