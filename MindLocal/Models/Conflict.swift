import Foundation
import SwiftData

/// An interpersonal conflict, argument, disagreement, or tension the writer
/// describes in an entry. Kept as its own record (not just an unpleasant
/// experience) so friction with a specific person can be filtered, counted, and
/// surfaced on that person's page. Links to the `Person` it was with when that
/// person resolves to a graph node.
@Model
final class Conflict {
    var id: UUID
    var createdAt: Date
    /// What the disagreement was about, in the writer's own words.
    var summary: String
    /// The raw name/relationship of who it was with, as extracted — kept as text
    /// even when it can't be resolved to a `Person` node (e.g. a bare "my manager").
    var personName: String
    /// How the writer felt about it. Empty if not stated.
    var feelings: String
    var resolutionRaw: String
    /// The entry this conflict was extracted from (inverse of `Experience.conflicts`).
    var experience: Experience?
    /// The person it was with, resolved to a graph node (nil if unresolved).
    @Relationship var withPerson: Person?

    var resolution: ConflictResolution {
        get { ConflictResolution(rawValue: resolutionRaw) ?? .unresolved }
        set { resolutionRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        summary: String,
        personName: String = "",
        feelings: String = "",
        resolution: ConflictResolution = .unresolved
    ) {
        self.id = id
        self.createdAt = createdAt
        self.summary = summary
        self.personName = personName
        self.feelings = feelings
        self.resolutionRaw = resolution.rawValue
    }
}

/// How a conflict stood at the time of writing.
enum ConflictResolution: String, Codable, CaseIterable, Identifiable {
    case resolved, unresolved, ongoing
    var id: String { rawValue }

    var label: String {
        switch self {
        case .resolved:   "Resolved"
        case .unresolved: "Unresolved"
        case .ongoing:    "Ongoing"
        }
    }

    var symbol: String {
        switch self {
        case .resolved:   "checkmark.circle"
        case .unresolved: "exclamationmark.bubble"
        case .ongoing:    "clock.arrow.2.circlepath"
        }
    }
}
