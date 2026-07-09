import Foundation
import UserNotifications

/// Schedules a gentle daily local notification nudging the user to record their
/// day. On-device; no server. Time is user-configurable (default 10:00 PM).
@MainActor
final class DailyReminderService {
    static let shared = DailyReminderService()

    private let identifier = "mindlocal.daily-journal-reminder"

    /// Asks for notification permission. Returns whether it's granted.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound])
        return granted ?? false
    }

    /// Schedules (replacing any existing) a daily repeating reminder.
    func schedule(hour: Int, minute: Int) async {
        guard await requestAuthorization() else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "MindLocal"
        content.body = "How was your day? Tap to share your journal."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
