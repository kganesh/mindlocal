import Foundation
import FoundationModels

/// Guided-generation target for a specific PAST activity in a diary entry that
/// involved a named person — "met David for coffee", "took Mom to her doctor's
/// appointment". Grounded in the note; an empty `with` means no specific person
/// was involved, so it's not event-worthy (a solo activity like "went for a run"
/// belongs only in `ExperienceDraft.activities`, never here).
///
/// The day this happened is never ambiguous — it's the entry's own date — so
/// unlike `AppointmentDraft`, only the TIME needs resolving afterward, by
/// `ActivityTimeResolver`. `timePhrase` is kept as the writer's own words for
/// the same reason `AppointmentDraft.whenPhrase` is: small on-device models get
/// relative/fuzzy time arithmetic wrong.
@Generable
struct ActivityEventDraft: Equatable {
    @Guide(description: "Short title for the activity (e.g. 'Coffee with David', 'Took Mom to her appointment').")
    var title: String

    @Guide(description: "The specific named person involved — by name or relationship (e.g. 'David', 'Mom'). Not a group, and not done alone.")
    var with: String

    @Guide(description: "What time of day it happened, exactly as the writer stated it (e.g. '4 o'clock', '4pm', 'in the afternoon', 'this morning'). Do NOT compute or normalize it.")
    var timePhrase: String
}

extension ActivityEventDraft {
    var isActivityEvent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !with.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// A detected past activity ready to become a real `Event` — the review screen
/// only shows these (same "Add to Events" pattern as `AppointmentCandidate`, so
/// the two read as one consistent feature to the user, not two). Purely
/// transient UI state; never persisted. Becomes a real `Event` only when the
/// user explicitly taps "Add to Events".
struct ActivityEventCandidate: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var personName: String
    var date: Date
    var isApproximateTime: Bool

    /// Builds candidates from extracted drafts, resolving each one's time
    /// against `day` — the entry's own date, not "now".
    static func candidates(from drafts: [ActivityEventDraft], day: Date) -> [ActivityEventCandidate] {
        drafts.filter { $0.isActivityEvent }.map { draft in
            let resolved = ActivityTimeResolver.resolve(timePhrase: draft.timePhrase, on: day)
            return ActivityEventCandidate(
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                personName: draft.with.trimmingCharacters(in: .whitespacesAndNewlines),
                date: resolved.date,
                isApproximateTime: resolved.isApproximate
            )
        }
    }
}
