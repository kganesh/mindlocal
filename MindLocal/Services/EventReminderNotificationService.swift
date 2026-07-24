import Foundation
import UserNotifications

/// Schedules a same-day local notification for an `Event` that's linked to a
/// `Person`, carrying that person's open `Reminder` items — "things to ask my
/// doctor" surfaces the morning of the appointment instead of staying buried in
/// the app. On-device; no server. One request per event, keyed by the event's id
/// so rescheduling (edit) or cancelling (delete, unlink, date in the past) is safe.
@MainActor
enum EventReminderNotificationService {
    private static func identifier(for eventId: UUID) -> String {
        "mindlocal.event-reminder.\(eventId.uuidString)"
    }

    /// Re-derives the notification for this event from its current state: cancels
    /// any existing request, then schedules a fresh one if the event has a linked
    /// person with open reminders and is still in the future. Call after creating
    /// or editing an event, and whenever a reminder for its linked person changes.
    static func reschedule(for event: Event) async {
        let id = identifier(for: event.id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])

        guard let person = event.person, event.date > .now else { return }
        let open = person.reminders.filter { !$0.isDone }
        guard !open.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(event.title) — things to remember"
        content.body = open.map { "• \($0.text)" }.joined(separator: "\n")
        content.sound = .default

        // Fire the morning of the event (9 AM) rather than at the exact event time,
        // so it's useful to glance at before walking in, not mid-appointment.
        var components = Calendar.current.dateComponents([.year, .month, .day], from: event.date)
        components.hour = 9
        components.minute = 0
        let fireDate = Calendar.current.date(from: components) ?? event.date
        // If 9 AM has already passed today (event later today), fire in a minute.
        let trigger: UNNotificationTrigger
        if fireDate <= .now {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        } else {
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Cancels the pending notification for an event, e.g. before it's deleted.
    static func cancel(for event: Event) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: event.id)])
    }

    /// Reschedules every future event linked to `person` — call after adding,
    /// editing, or checking off a reminder so any already-scheduled notification
    /// reflects the current open list.
    static func rescheduleAll(for person: Person, events: [Event]) async {
        for event in events where event.person === person && event.date > .now {
            await reschedule(for: event)
        }
    }

    /// Fires shortly after saving to prompt adding a detected appointment to
    /// Events — the only way to ask when there's no interactive review screen,
    /// e.g. the Siri "log my day" intent, which saves straight through. Does NOT
    /// create the Event itself; tapping through to the app is still required.
    static func promptToAddAppointment(_ candidate: AppointmentCandidate) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Add this to your calendar?"
        var body = candidate.title
        if !candidate.personName.isEmpty { body += " with \(candidate.personName)" }
        body += " — \(candidate.date.formatted(date: .abbreviated, time: .shortened))"
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "mindlocal.appointment-prompt.\(candidate.id.uuidString)",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
}
