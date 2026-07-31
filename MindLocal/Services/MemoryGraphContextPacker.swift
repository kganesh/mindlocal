import Foundation

/// Converts graph retrieval results into a compact, source-oriented context
/// block for the advisor prompt. The retriever decides what is relevant; this
/// packer keeps the LLM payload readable and bounded.
enum MemoryGraphContextPacker {
    static func pack(_ result: MemoryGraphRetrievalResult, maxNodes: Int = 14, maxEdges: Int = 18) -> String {
        let evidence = Array(result.evidenceNodes
            .sorted(by: sortEvidence)
            .prefix(maxNodes))
        let evidenceIDs = Set(evidence.map(\.id))
        let relatedLimit = max(0, maxNodes - evidence.count)
        let related = Array(result.expandedNodes
            .filter { !evidenceIDs.contains($0.id) }
            .sorted(by: sortEvidence)
            .prefix(relatedLimit))

        var blocks: [String] = []

        // Placed first and stated as a computed fact, not left for the model to
        // derive from Evidence below — small on-device models are unreliable at
        // scanning several dated lines and picking the true maximum themselves.
        if let mostRecent = result.mostRecentInteraction {
            blocks.append(
                "MOST RECENT WITH \(mostRecent.person.displayName) (computed, authoritative — state this date directly, do not re-derive a different one from Evidence below):\n"
                + line(for: mostRecent.node)
            )
        }

        if !result.intent.mentionedPeople.isEmpty {
            let people = result.intent.mentionedPeople
                .map { "\($0.displayName) matched \"\($0.matchedPhrase)\" as \($0.matchKind.rawValue)" }
                .joined(separator: "; ")
            blocks.append("Resolved people: \(people)")
        }

        let evidenceLines = evidence.enumerated().map { index, node in
            "\(index + 1). \(line(for: node))"
        }
        if !evidenceLines.isEmpty {
            blocks.append("Evidence:\n" + evidenceLines.joined(separator: "\n"))
        }

        let relatedLines = related.enumerated().map { index, node in
            "\(index + 1). \(line(for: node))"
        }
        if !relatedLines.isEmpty {
            blocks.append("Related signals:\n" + relatedLines.joined(separator: "\n"))
        }

        let edgeLines = result.edges
            .prefix(maxEdges)
            .map { "\($0.from.rawValue) --\($0.kind.rawValue)--> \($0.to.rawValue)\($0.label.isEmpty ? "" : " (\($0.label))")" }
        if !edgeLines.isEmpty {
            blocks.append("Useful links:\n" + edgeLines.joined(separator: "\n"))
        }

        return blocks.isEmpty ? "" : blocks.joined(separator: "\n\n")
    }

    private static func sortEvidence(_ lhs: MemoryNode, _ rhs: MemoryNode) -> Bool {
        let lhsPriority = priority(lhs)
        let rhsPriority = priority(rhs)
        if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
        return (lhs.date ?? .distantPast) > (rhs.date ?? .distantPast)
    }

    private static func priority(_ node: MemoryNode) -> Int {
        switch node.kind {
        case .reminder:
            node.properties["isDone"] == "false" ? 90 : 45
        case .event:
            80
        case .entry:
            70
        case .decision:
            65
        case .conflict:
            60
        case .person:
            50
        default:
            20
        }
    }

    private static func line(for node: MemoryNode) -> String {
        var parts = ["[\(node.kind.rawValue)\(dateSuffix(node.date))] \(node.title)"]
        if !node.summary.isEmpty {
            parts.append(clip(node.summary))
        }

        let detailKeys = [
            "entryKind", "domain", "tone", "location", "isDone",
            "startDate", "endDate", "sourceType"
        ]
        let details = detailKeys.compactMap { key -> String? in
            guard let value = node.properties[key], !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }
        if !details.isEmpty {
            parts.append("(\(details.joined(separator: ", ")))")
        }
        return parts.joined(separator: " ")
    }

    private static func dateSuffix(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return ", \(formatter.string(from: date))"
    }

    private static func clip(_ text: String, max: Int = 180) -> String {
        text.count <= max ? text : String(text.prefix(max)) + "..."
    }
}
