import Foundation

/// A name the journal mentions but People doesn't contain, plus the entries
/// that mention it.
struct UnresolvedPersonMention: Equatable {
    struct Mention: Equatable {
        let title: String
        let date: Date?
    }

    /// The name as the entries actually spell it, not as the question spelled it.
    let name: String
    /// Most recent first, capped at `UnresolvedPersonFinder.maxMentions`.
    let mentions: [Mention]
    /// How many mentions exist in the window, before the cap.
    let totalCount: Int

    /// Deterministic answer — assembled from node titles and dates, never a
    /// model call, so it cannot invent a relationship. It says only what the
    /// graph supports: that the name was mentioned, and where. "Tommy is your
    /// brother" would need a PersonRelationship edge, and there isn't one.
    var answerText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let cited = mentions.map { mention -> String in
            guard let date = mention.date else { return "\"\(mention.title)\"" }
            return "\"\(mention.title)\" (\(formatter.string(from: date)))"
        }

        var text = "\(name) isn't in your People list, but your journal mentions "
        text += totalCount == 1 ? "them once: " : "them \(totalCount) times. "
        if totalCount > 1 {
            text += mentions.count == totalCount ? "In: " : "Most recent: "
        }
        text += cited.joined(separator: ", ")
        if totalCount > mentions.count {
            text += ", and \(totalCount - mentions.count) more"
        }
        text += ".\n\nWould you like to add \(name) to your People list? "
        text += "Adding them links these entries to their profile."
        return text
    }
}

/// Finds a name that appears in the journal but not in People.
///
/// `MemoryGraphBuilder` already records this state: a raw extracted name that
/// matches no `Person` becomes a `.person` node with `resolved == "false"`
/// (`person-unresolved:<slug>`), joined to the record that named it. This reads
/// that back, so "who is Tommy?" can distinguish two very different answers —
/// "I've never heard of Tommy" from "you've mentioned Tommy three times but
/// never added them."
///
/// Note the state is transient by design: the builder re-checks every raw name
/// against who is known on each rebuild (`MemoryGraphBuilder:110`), so adding
/// the person makes the unresolved node disappear and the entries attach to the
/// real profile.
enum UnresolvedPersonFinder {

    /// How far back to look. Applied explicitly rather than assumed from the
    /// graph's own scope: `MemoryGraphStore.rebuildAndPersist` fetches every
    /// record with no date predicate, so the graph is NOT limited to a year.
    static let lookbackWindow: TimeInterval = 365 * 86_400

    /// Cited mentions are capped — enough to show the pattern without turning
    /// the answer into a list.
    static let maxMentions = 3

    static func find(name: String,
                     in graph: MemoryGraph,
                     now: Date = .now) -> UnresolvedPersonMention? {
        let needle = normalize(name)
        guard !needle.isEmpty else { return nil }

        let unresolvedNodes = graph.nodes.filter { node in
            node.kind == .person
                && node.properties["resolved"] == "false"
                && matches(needle, nodeTitle: node.title)
        }
        guard !unresolvedNodes.isEmpty else { return nil }

        let nodesByID = Dictionary(graph.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let unresolvedIDs = Set(unresolvedNodes.map(\.id))
        let cutoff = now.addingTimeInterval(-lookbackWindow)

        // Records point AT the person (entry --mentions-->, conflict
        // --withPerson-->, reminder --aboutPerson-->), so the record is the
        // edge's `from` side.
        var seen = Set<MemoryNodeID>()
        var records: [MemoryNode] = []
        for edge in graph.edges where unresolvedIDs.contains(edge.to) {
            guard let record = nodesByID[edge.from],
                  MemoryGraphRetrievalResult.evidenceKind(record.kind),
                  seen.insert(record.id).inserted else { continue }
            // Undated records are kept: they can't be shown to fall outside the
            // window, and dropping a real mention is worse than including one
            // that may be older than a year.
            if let date = record.date, date < cutoff { continue }
            records.append(record)
        }
        guard !records.isEmpty else { return nil }

        let sorted = records.sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (l?, r?): return l > r
            case (nil, _?):    return false
            case (_?, nil):    return true
            case (nil, nil):   return lhs.title < rhs.title
            }
        }

        return UnresolvedPersonMention(
            // Prefer the journal's own spelling over the question's.
            name: unresolvedNodes.first?.title ?? name,
            mentions: sorted.prefix(maxMentions).map { .init(title: $0.title, date: $0.date) },
            totalCount: sorted.count
        )
    }

    /// A question may say "Tommy" where an entry says "Tommy Nolan", or the
    /// reverse — match on the whole string or on any word of it.
    private static func matches(_ needle: String, nodeTitle: String) -> Bool {
        let title = normalize(nodeTitle)
        if title == needle { return true }
        let titleWords = title.split(separator: " ").map(String.init)
        let needleWords = needle.split(separator: " ").map(String.init)
        return titleWords.contains(needle) || needleWords.contains(title)
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
