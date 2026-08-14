import Foundation
import FoundationModels

/// Guided-generation target for an action item tied to a future interaction with
/// a specific person, extracted from an entry. Grounded in the note — an empty
/// `about` means "not a real reminder" and is dropped, mirroring `ConflictDraft`.
@Generable
struct ReminderDraft: Equatable {
    @Guide(description: "Who this reminder is about — a specific person by name or relationship (e.g. 'Dr. Chotai', 'my manager').")
    var with: String

    @Guide(description: "What to remember or ask, phrased as a short action item in the writer's own words (e.g. 'ask about the referral', 'bring up the raise').")
    var about: String
}

extension ReminderDraft {
    var isReminder: Bool {
        !about.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toReminder() -> Reminder {
        Reminder(
            text: about.trimmingCharacters(in: .whitespacesAndNewlines),
            personName: with.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
