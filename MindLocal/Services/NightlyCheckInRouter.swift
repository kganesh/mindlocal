import Foundation
import UserNotifications

/// Routes a tapped daily-reminder notification to the nightly voice check-in.
/// Acts as the notification-center delegate; sets `isActive` when the reminder
/// is opened, which the root view observes to present the conversation.
@Observable
@MainActor
final class NightlyCheckInRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NightlyCheckInRouter()

    var isActive = false

    /// Register as the notification delegate. Call once at launch.
    func register() {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        Task { @MainActor in
            if identifier == DailyReminderService.reminderIdentifier {
                self.isActive = true
            }
            completionHandler()
        }
    }

    /// Show the reminder as a banner even when the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
