import Foundation
import FoundationModels

/// Guided-generation target for a specific upcoming appointment mentioned in an
/// entry — "next Tuesday", "my follow-up in two weeks". Grounded in the note; an
/// empty `whenPhrase` means no specific date was stated, so it's not an appointment
/// (a bare intention with no date belongs in reminders/hopes instead).
///
/// Deliberately does NOT ask the model to compute a date — relative-date
/// arithmetic ("next Tuesday" → an actual calendar date) is exactly what small
/// on-device models get wrong. `whenPhrase` is kept as the writer's own words and
/// resolved deterministically afterward by `AppointmentDateResolver`.
@Generable
struct AppointmentDraft: Equatable {
    @Guide(description: "Who the appointment is with — a specific person by name or relationship (e.g. 'Dr. Chotai', 'the specialist'). Empty if not tied to a specific person.")
    var with: String

    @Guide(description: "Short title for the appointment (e.g. 'Wisdom tooth extraction', 'Follow-up visit'). Empty if not a real appointment.")
    var title: String

    @Guide(description: "The date/time exactly as the writer stated it (e.g. 'next Tuesday', 'in two weeks', 'August 15th at 2pm'). Do NOT compute or normalize this into a calendar date — keep their original wording. Empty if no specific date or time was mentioned.")
    var whenPhrase: String
}

extension AppointmentDraft {
    var isAppointment: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !whenPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// A detected appointment with its date successfully resolved — the review
/// screen only ever shows these (an unresolved phrase has nothing actionable to
/// offer, so it's silently dropped rather than shown as a dead-end card).
/// Purely transient UI state; never persisted. Becomes a real `Event` only when
/// the user explicitly taps "Add to Events".
struct AppointmentCandidate: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var personName: String
    var whenPhrase: String
    var date: Date

    /// Builds candidates from extracted drafts, keeping only those whose phrase
    /// resolved to an actual date.
    static func candidates(from drafts: [AppointmentDraft]) -> [AppointmentCandidate] {
        drafts.filter { $0.isAppointment }.compactMap { draft in
            guard let date = AppointmentDateResolver.resolve(draft.whenPhrase) else { return nil }
            return AppointmentCandidate(
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                personName: draft.with.trimmingCharacters(in: .whitespacesAndNewlines),
                whenPhrase: draft.whenPhrase.trimmingCharacters(in: .whitespacesAndNewlines),
                date: date
            )
        }
    }
}
