import Foundation

/// Converts graph retrieval results into a compact, source-oriented context
/// block for the advisor prompt. The retriever decides what is relevant; this
/// packer keeps the LLM payload readable and bounded.
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

    static func pack(_ result: MemoryGraphRetrievalResult, maxNodes: Int = 10, maxEdges: Int = 12) -> String {
        packWithManifest(result, maxNodes: maxNodes, maxEdges: maxEdges).text
    }

    static func packWithManifest(_ result: MemoryGraphRetrievalResult, maxNodes: Int = 10, maxEdges: Int = 12) -> PackedContext {
        // `result.evidenceNodes`/`expandedNodes` already arrive ordered by the
        // retriever's relevance score (person-connection + structured-intent +
        // text-match boosts). Select the top `maxNodes` by that order AND
        // keep them in that order for display — a kind/date re-sort here
        // (event > entry > conflict, then most-recent-first, tried
        // previously) let an utterly unrelated but higher-kind-priority
        // event ("Wisdom tooth extraction") land ahead of the actually
        // relevant conflict entry in the composed string. That's exactly
        // backwards once AdviceService's outer character budget has to
        // truncate: it cuts from the END of the string, so anything sorted
        // later — even the single most relevant item — is the first thing to
        // get silently dropped. Relevance order first means the most
        // important evidence is always closest to the front, and the least
        // relevant is what a tight budget trims away.
        let evidence = Array(result.evidenceNodes.prefix(maxNodes))
        let evidenceIDs = Set(evidence.map(\.id))
        let relatedLimit = max(0, maxNodes - evidence.count)
        let related = Array(result.expandedNodes
            .filter { !evidenceIDs.contains($0.id) }
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

        // Resolves an edge endpoint to its actual title (a person's name, an
        // event's title, …) instead of the bare internal ID — this previously
        // fed the model lines like "person:2412D008-CC51-4F2E... --relatedTo-->
        // person:B14948F4..." with no indication of who those UUIDs actually
        // were, sitting right next to the correctly-named PEOPLE/Evidence
        // blocks. Opaque, unresolvable noise like that is exactly the kind of
        // thing that can derail an already-fragile identity question.
        let nodesByID: [MemoryNodeID: MemoryNode] = Dictionary(
            (result.seedNodes + result.expandedNodes).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        func label(for id: MemoryNodeID) -> String {
            if let title = nodesByID[id]?.title, !title.isEmpty { return title }
            let kind = id.rawValue.split(separator: ":").first.map(String.init) ?? "record"
            return "a \(kind)"
        }

        // .relatedTo edges are built one-for-one from PersonRelationship — the
        // exact same facts PersonContextBuilder already states unambiguously in
        // the PEOPLE block above ("You are Parent of Aditya Kolekar."). Once
        // resolved to real names, "Akhil Kolekar --relatedTo--> Ganesh Kolekar
        // (Child)" is genuinely ambiguous prose — it doesn't say which side is
        // the child — and having proven the model can misread that direction
        // (producing "Ganesh Kolekar is your parent"), these are worse than
        // useless here: pure duplication with a real chance of contradicting
        // the correct PEOPLE block right above it. Drop them.
        let edgeLines = result.edges
            .filter { $0.kind != .relatedTo }
            .prefix(maxEdges)
            .map { "\(label(for: $0.from)) --\($0.kind.rawValue)--> \(label(for: $0.to))\($0.label.isEmpty ? "" : " (\($0.label))")" }
        if !edgeLines.isEmpty {
            blocks.append("Useful links:\n" + edgeLines.joined(separator: "\n"))
        }

        // Everything the validator is allowed to treat as "the model was told
        // this". Drawn from the same arrays that composed the blocks above, so
        // the manifest can't drift from what was actually sent.
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let shown = evidence + related
        var knownPeople = Set(result.intent.mentionedPeople.map(\.displayName))
        knownPeople.formUnion(shown.filter { $0.kind == .person }.map(\.title))
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
