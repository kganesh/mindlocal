import Foundation
import SwiftData

/// Turns an accepted `ActivityEventCandidate` into a real `Event` — same
/// pattern as `AppointmentEventBuilder`, so a past activity and a future
/// appointment become indistinguishable once they're both real events.
@MainActor
enum ActivityEventBuilder {
    static func createEvent(from candidate: ActivityEventCandidate, in context: ModelContext) async {
        let person: Person? = candidate.personName.isEmpty
            ? nil
            : PersonResolver.resolve([candidate.personName], in: context).first
        let event = Event(
            title: candidate.title,
            date: candidate.date,
            isApproximateTime: candidate.isApproximateTime,
            person: person
        )
        context.insert(event)
        EmbeddingService.embed(event)
        if let person {
            await EventReminderNotificationService.rescheduleAll(for: person, events: [event])
        }
    }
}
