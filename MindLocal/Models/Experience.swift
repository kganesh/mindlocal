import Foundation
import SwiftData

/// The intent of an entry. Daily logs are broad reflections for a day; experience
/// entries are specific moments that happened within that day.
enum ExperienceKind: String, Codable, CaseIterable, Identifiable {
    case dailyLog
    case experience

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dailyLog: "Daily Log"
        case .experience: "Experience"
        }
    }

    var symbol: String {
        switch self {
        case .dailyLog: "book.pages"
        case .experience: "text.book.closed"
        }
    }
}

/// A lived experience (distinct from a Decision): something that happened to the
/// user, stored as-is plus extracted content. Pleasant experiences help the user
/// recreate them; unpleasant ones help them handle similar situations better.
@Model
final class Experience {
    var id: UUID
    var createdAt: Date
    var title: String
    /// What happened.
    var summary: String
    /// Emotions the person expressed.
    var feelings: String
    var toneRaw: String
    /// What made it pleasant or unpleasant.
    var factors: String
    /// What the person did / how they responded.
    var response: String
    /// Takeaway — what to repeat (pleasant) or do differently (unpleasant).
    var learning: String
    var tags: [String]
    var domainRaw: String
    var rawText: String?
    var embedding: [Float]
    /// Whether this entry is the broad daily reflection or a specific experience.
    /// Empty/default values from older stores read as `.experience`.
    var kindRaw: String = ExperienceKind.experience.rawValue
    /// When the experience actually happened (for the timeline). Optional so
    /// existing records migrate cleanly; falls back to `createdAt`.
    var occurredAt: Date?
    /// Semantic extraction for journaling (additive; default empty for migration).
    var people: [String] = []
    var activities: [String] = []
    var outcomes: [String] = []
    /// Forward-looking wants / wishes / hopes.
    var hopes: [String] = []
    /// Health context for the entry's day, from HealthKit (nil if unavailable /
    /// not connected). Additive; defaults keep existing records migrating cleanly.
    var sleepHours: Double? = nil
    var steps: Int? = nil
    var workoutMinutes: Double? = nil
    var workoutCount: Int? = nil
    /// Where the moment happened (optional). Additive; empty/nil for migration.
    var location: String = ""
    var latitude: Double? = nil
    var longitude: Double? = nil
    /// Decisions the person mentioned within this experience (extracted by AI).
    @Relationship(deleteRule: .cascade, inverse: \Decision.experience)
    var decisions: [Decision] = []
    /// Interpersonal conflicts/arguments mentioned in this entry (extracted by AI),
    /// each optionally linked to the `Person` it was with.
    @Relationship(deleteRule: .cascade, inverse: \Conflict.experience)
    var conflicts: [Conflict] = []
    /// Action items tied to a future interaction with someone, mentioned in this
    /// entry (extracted by AI), each optionally linked to the `Person` it's about.
    @Relationship(deleteRule: .cascade, inverse: \Reminder.experience)
    var reminders: [Reminder] = []
    /// People mentioned in this entry, resolved to graph nodes (inverse defined
    /// on `Person.experiences`). The raw `people` strings stay as-is.
    @Relationship var linkedPeople: [Person] = []

    var tone: ExperienceTone {
        get { ExperienceTone(rawValue: toneRaw) ?? .mixed }
        set { toneRaw = newValue.rawValue }
    }
    var domain: Domain {
        get { Domain(rawValue: domainRaw) ?? .other }
        set { domainRaw = newValue.rawValue }
    }
    var kind: ExperienceKind {
        get { ExperienceKind(rawValue: kindRaw) ?? .experience }
        set { kindRaw = newValue.rawValue }
    }
    /// Chronological anchor for the timeline.
    var timelineDate: Date { occurredAt ?? createdAt }
    /// Whether any HealthKit context is attached to this entry.
    var hasHealthContext: Bool { sleepHours != nil || steps != nil || (workoutCount ?? 0) > 0 }
    /// Whether a place is associated with this entry.
    var hasLocation: Bool { !location.isEmpty }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        title: String,
        summary: String,
        feelings: String = "",
        tone: ExperienceTone = .mixed,
        factors: String = "",
        response: String = "",
        learning: String = "",
        tags: [String] = [],
        domain: Domain = .other,
        kind: ExperienceKind = .experience,
        rawText: String? = nil,
        embedding: [Float] = [],
        occurredAt: Date? = nil,
        people: [String] = [],
        activities: [String] = [],
        outcomes: [String] = [],
        hopes: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.occurredAt = occurredAt
        self.title = title
        self.summary = summary
        self.feelings = feelings
        self.toneRaw = tone.rawValue
        self.factors = factors
        self.response = response
        self.learning = learning
        self.tags = tags
        self.domainRaw = domain.rawValue
        self.kindRaw = kind.rawValue
        self.rawText = rawText
        self.embedding = embedding
        self.people = people
        self.activities = activities
        self.outcomes = outcomes
        self.hopes = hopes
    }
}
