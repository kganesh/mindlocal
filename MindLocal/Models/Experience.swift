import Foundation
import SwiftData

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
    /// When the experience actually happened (for the timeline). Optional so
    /// existing records migrate cleanly; falls back to `createdAt`.
    var occurredAt: Date?
    /// Decisions the person mentioned within this experience (extracted by AI).
    @Relationship(deleteRule: .cascade, inverse: \Decision.experience)
    var decisions: [Decision] = []

    var tone: ExperienceTone {
        get { ExperienceTone(rawValue: toneRaw) ?? .mixed }
        set { toneRaw = newValue.rawValue }
    }
    var domain: Domain {
        get { Domain(rawValue: domainRaw) ?? .other }
        set { domainRaw = newValue.rawValue }
    }
    /// Chronological anchor for the timeline.
    var timelineDate: Date { occurredAt ?? createdAt }

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
        rawText: String? = nil,
        embedding: [Float] = [],
        occurredAt: Date? = nil
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
        self.rawText = rawText
        self.embedding = embedding
    }
}
