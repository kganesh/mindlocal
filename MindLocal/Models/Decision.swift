import Foundation
import SwiftData

@Model
final class Decision {
    var id: UUID
    var createdAt: Date
    var title: String
    var statement: String
    var context: String
    @Relationship(deleteRule: .cascade) var options: [OptionConsidered]
    var rationale: String
    /// What the person optimized for in this choice (the you-model's atoms).
    /// Additive; default empty for clean migration.
    var valuesPrioritized: [String] = []
    /// What they consciously gave up for it.
    var valuesTradedOff: [String] = []
    var domainRaw: String
    var stakesRaw: String
    var revisitAt: Date?
    @Relationship(deleteRule: .cascade) var outcome: Outcome?
    var rawTranscript: String?
    var embedding: [Float]   // populated in M2; empty in M1
    /// When the decision was actually made (for the timeline). Optional so
    /// existing records migrate cleanly; falls back to `createdAt`.
    var occurredAt: Date?
    /// The experience this decision was extracted from, if any (nil = standalone).
    var experience: Experience?

    var domain: Domain {
        get { Domain(rawValue: domainRaw) ?? .other }
        set { domainRaw = newValue.rawValue }
    }
    var stakes: Stakes {
        get { Stakes(rawValue: stakesRaw) ?? .medium }
        set { stakesRaw = newValue.rawValue }
    }
    /// Chronological anchor for the timeline.
    var timelineDate: Date { occurredAt ?? createdAt }

    // MARK: - Decision → outcome loop (Phase 1)

    /// How long after a decision we prompt to record how it turned out, by stakes.
    /// Low-stakes decisions aren't scheduled for revisit (nil).
    static func revisitDelay(for stakes: Stakes) -> TimeInterval? {
        switch stakes {
        case .high:   30 * 86_400   // ~1 month
        case .medium: 14 * 86_400   // ~2 weeks
        case .low:    nil           // skip
        }
    }

    /// The revisit date for a decision made at `occurredAt` with the given stakes.
    static func revisitDate(for stakes: Stakes, occurredAt: Date) -> Date? {
        revisitDelay(for: stakes).map { occurredAt.addingTimeInterval($0) }
    }

    /// Due to be revisited: scheduled, past its revisit date, and no outcome yet.
    func isDueForRevisit(asOf now: Date = .now) -> Bool {
        guard outcome == nil, let revisitAt else { return false }
        return revisitAt <= now
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        title: String,
        statement: String,
        context: String = "",
        options: [OptionConsidered] = [],
        rationale: String = "",
        valuesPrioritized: [String] = [],
        valuesTradedOff: [String] = [],
        domain: Domain = .other,
        stakes: Stakes = .medium,
        revisitAt: Date? = nil,
        rawTranscript: String? = nil,
        embedding: [Float] = [],
        occurredAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.occurredAt = occurredAt
        self.title = title
        self.statement = statement
        self.context = context
        self.options = options
        self.rationale = rationale
        self.valuesPrioritized = valuesPrioritized
        self.valuesTradedOff = valuesTradedOff
        self.domainRaw = domain.rawValue
        self.stakesRaw = stakes.rawValue
        self.revisitAt = revisitAt
        self.outcome = nil
        self.rawTranscript = rawTranscript
        self.embedding = embedding
    }
}

@Model
final class OptionConsidered {
    var text: String
    var rejectedBecause: String?

    init(text: String, rejectedBecause: String? = nil) {
        self.text = text
        self.rejectedBecause = rejectedBecause
    }
}

@Model
final class Outcome {
    var recordedAt: Date
    var resultRaw: String
    var notes: String

    var result: OutcomeResult {
        get { OutcomeResult(rawValue: resultRaw) ?? .tooEarly }
        set { resultRaw = newValue.rawValue }
    }

    init(recordedAt: Date = .now, result: OutcomeResult, notes: String = "") {
        self.recordedAt = recordedAt
        self.resultRaw = result.rawValue
        self.notes = notes
    }
}
