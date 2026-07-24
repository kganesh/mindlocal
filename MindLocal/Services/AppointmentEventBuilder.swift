import Foundation
import SwiftData

/// Turns an accepted `AppointmentCandidate` into a real `Event` — resolves the
/// named person the same way entries do, inserts it, and reschedules that
/// person's reminder notification so it picks up the newly added event if they
/// already have open reminders.
@MainActor
enum AppointmentEventBuilder {
    static func createEvent(from candidate: AppointmentCandidate, in context: ModelContext) async {
        let person: Person? = candidate.personName.isEmpty
            ? nil
            : PersonResolver.resolve([candidate.personName], in: context).first
        let event = Event(title: candidate.title, date: candidate.date, person: person)
        context.insert(event)
        EmbeddingService.embed(event)
        if let person {
            await EventReminderNotificationService.rescheduleAll(for: person, events: [event])
        }
    }
}
