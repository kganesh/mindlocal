import Foundation
import SwiftData

/// An action item the writer wants to remember for a future interaction with a
/// specific person — "ask my doctor about the referral," "bring up the raise
/// with my manager." Kept as its own record (not folded into hopes) so it can be
/// checked off on that person's page, or surface as a notification when an
/// `Event` with them is scheduled.
@Model
final class Reminder {
    var id: UUID
    var createdAt: Date
    /// What to remember or ask, in the writer's own words.
    var text: String
    var isDone: Bool
    var doneAt: Date?
    /// The raw name/relationship of who it's about, as extracted — kept even when
    /// it can't be resolved to a `Person` node (mirrors `Conflict.personName`).
    var personName: String
    /// The entry this reminder was extracted from (inverse of `Experience.reminders`).
    var experience: Experience?
    /// The person it's about, resolved to a graph node (nil if unresolved).
    @Relationship var person: Person?
    /// On-device sentence embedding for semantic retrieval in Advise. Empty until
    /// computed at save time (mirrors `Experience.embedding`/`Decision.embedding`).
    var embedding: [Float] = []

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        text: String,
        personName: String = "",
        isDone: Bool = false,
        doneAt: Date? = nil,
        embedding: [Float] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.personName = personName
        self.isDone = isDone
        self.doneAt = doneAt
        self.embedding = embedding
    }

    func markDone() {
        isDone = true
        doneAt = .now
    }

    func markNotDone() {
        isDone = false
        doneAt = nil
    }
}
