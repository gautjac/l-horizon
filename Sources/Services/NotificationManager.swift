import Foundation
import UserNotifications

/// Schedules a local reminder for each intention when its next review falls due.
/// Overdue intentions (next-due already past) surface as an in-app banner instead
/// of a notification, so the user isn't pinged for something already on screen.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let prefix = "horizon.review."

    /// Ask once; harmless to call on every launch.
    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Replace our pending review reminders with a fresh set from the intentions'
    /// current cadence + last-reviewed dates. No-op if not authorized.
    func rescheduleReviewReminders(_ intentions: [Intention], lang: Lang) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        let pending = await center.pendingNotificationRequests()
        let mine = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: mine)

        let now = Date()
        for intention in intentions {
            let due = intention.nextReviewDue
            guard due > now else { continue }   // overdue → handled by the banner

            let content = UNMutableNotificationContent()
            content.title = lang == .fr ? "Revue attendue" : "Review due"
            content.body = lang == .fr
                ? "« \(intention.title) » — c'est le moment de faire le point."
                : "“\(intention.title)” — time to take stock."
            content.sound = .default

            let comps = Calendar.horizon.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: prefix + intention.id.uuidString,
                                                content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
