import Foundation
import SwiftData

/// Stable graph identifier. Prefixes encode the source/type (`person:`,
/// `entry:`, `activity:`), keeping IDs readable in logs and future citations.
struct MemoryNodeID: Hashable, Codable, Sendable, RawRepresentable {
    var rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
}

enum MemoryNodeKind: String, Codable, Sendable {
    case person
    case relationship
    case entry
    case event
    case decision
    case reminder
    case conflict
    case activity
    case outcome
    case hope
    case location
    case domain
    case tone
}

enum MemoryEdgeKind: String, Codable, Sendable {
    case mentions
    case relatedTo
    case hasEntry
    case hasEvent
    case hasDecision
    case hasReminder
    case hasConflict
    case hasActivity
    case hasOutcome
    case hasHope
    case happenedAt
    case inDomain
    case hasTone
    case sourceExperience
    case aboutPerson
    case withPerson
}

struct MemoryNode: Identifiable, Hashable, Codable, Sendable {
    var id: MemoryNodeID
    var kind: MemoryNodeKind
    var title: String
    var summary: String
    var date: Date?
    var sourceID: String?
    var properties: [String: String]

    init(
        id: MemoryNodeID,
        kind: MemoryNodeKind,
        title: String,
        summary: String = "",
        date: Date? = nil,
        sourceID: String? = nil,
        properties: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.date = date
        self.sourceID = sourceID
        self.properties = properties
    }
}

struct MemoryEdge: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var from: MemoryNodeID
    var to: MemoryNodeID
    var kind: MemoryEdgeKind
    var label: String
    var properties: [String: String]

    init(
        from: MemoryNodeID,
        to: MemoryNodeID,
        kind: MemoryEdgeKind,
        label: String = "",
        properties: [String: String] = [:]
    ) {
        self.from = from
        self.to = to
        self.kind = kind
        self.label = label
        self.properties = properties
        self.id = "\(from.rawValue)|\(kind.rawValue)|\(to.rawValue)|\(label)"
    }
}

struct MemoryGraph: Codable, Sendable {
    var builtAt: Date
    var nodes: [MemoryNode]
    var edges: [MemoryEdge]
    var sourceFingerprint: String

    static let empty = MemoryGraph(builtAt: .now, nodes: [], edges: [], sourceFingerprint: "")
}

/// On-device cache of the derived graph. The graph is derived, not user-authored:
/// it can be rebuilt from SwiftData records, but persisting the snapshot avoids
/// rebuilding for every future LLM query.
@Model
final class MemoryGraphSnapshot {
    var id: UUID
    var builtAt: Date
    var sourceFingerprint: String
    var graphData: Data

    init(
        id: UUID = UUID(),
        builtAt: Date = .now,
        sourceFingerprint: String = "",
        graph: MemoryGraph = .empty
    ) {
        self.id = id
        self.builtAt = builtAt
        self.sourceFingerprint = sourceFingerprint
        self.graphData = (try? JSONEncoder.memoryGraph.encode(graph)) ?? Data()
    }

    var graph: MemoryGraph {
        get {
            (try? JSONDecoder.memoryGraph.decode(MemoryGraph.self, from: graphData)) ?? .empty
        }
        set {
            builtAt = newValue.builtAt
            sourceFingerprint = newValue.sourceFingerprint
            graphData = (try? JSONEncoder.memoryGraph.encode(newValue)) ?? Data()
        }
    }
}

extension JSONEncoder {
    static var memoryGraph: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var memoryGraph: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
