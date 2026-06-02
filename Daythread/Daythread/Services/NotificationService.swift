//
//  NotificationService.swift
//  Daythread
//
//  Schedules and cancels UNUserNotificationCenter reminders for TripEvents.
//  Uses a "nuke & pave" approach: cancel the existing request then reschedule
//  whenever an event is saved or moved. The event UUID is the notification ID.
//
//  Requires the "Time Sensitive Notifications" capability in Xcode
//  (Target → Signing & Capabilities → +Capability → Time Sensitive Notifications).
//

import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    static let globalToggleKey   = "daythread.notificationsEnabled"
    static let reminderOffsetKey = "daythread.reminderMinutesBefore"
    static let reminderTypeKey   = "daythread.reminderType"

    private let center = UNUserNotificationCenter.current()

    private var notificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.globalToggleKey) as? Bool ?? true
    }
    private var reminderMinutes: Int {
        UserDefaults.standard.object(forKey: Self.reminderOffsetKey) as? Int ?? 15
    }
    /// Whether in-app (UNUserNotificationCenter) reminders should fire.
    var appNotificationsActive: Bool {
        guard notificationsEnabled else { return false }
        let type = UserDefaults.standard.string(forKey: Self.reminderTypeKey) ?? "app"
        return type == "app" || type == "both"
    }
    /// Whether Apple Calendar alarms (EKAlarm) should be attached to events.
    var calendarAlarmsActive: Bool {
        guard notificationsEnabled else { return false }
        let type = UserDefaults.standard.string(forKey: Self.reminderTypeKey) ?? "app"
        return type == "calendar" || type == "both"
    }

    private init() {}

    // MARK: — Authorization

    func requestAuthorization() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge, .providesAppNotificationSettings])
    }

    // MARK: — Category registration (call once at app launch)

    func registerCategories() {
        let snooze = UNNotificationAction(
            identifier: "DAYTHREAD_SNOOZE",
            title: "Snooze 15 min",
            options: []
        )
        let view = UNNotificationAction(
            identifier: "DAYTHREAD_VIEW",
            title: "View Itinerary",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "DAYTHREAD_EVENT",
            actions: [snooze, view],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    // MARK: — Schedule

    /// Cancels any existing reminder for this event and schedules a fresh one
    /// using the current global reminder offset. No-op if notifications are
    /// disabled globally, the event is untimed, or it has no assigned day.
    func schedule(_ event: TripEvent) {
        guard let id = event.id else { return }
        cancel(id: id)
        guard appNotificationsActive else { return }

        let tz: TimeZone
        if let td = event.transitDetails {
            tz = TimeZone(identifier: td.departureTZIdentifier) ?? .current
        } else {
            tz = .current
        }
        guard let start = event.eventStart(in: tz) else { return }

        let fireDate = start.addingTimeInterval(-Double(reminderMinutes * 60))
        guard fireDate > Date() else { return }     // don't schedule past events

        let tripName = event.day?.trip?.name ?? "Daythread"
        let content  = UNMutableNotificationContent()
        content.title               = event.title.isEmpty ? "(Untitled)" : event.title
        content.body                = reminderBody(for: event, tripName: tripName, start: start, tz: tz)
        content.sound               = .default
        content.interruptionLevel   = .timeSensitive
        content.threadIdentifier    = event.day?.trip?.id?.uuidString ?? ""
        content.categoryIdentifier  = "DAYTHREAD_EVENT"
        content.userInfo            = [
            "eventID": id.uuidString,
            "tripID":  event.day?.trip?.id?.uuidString ?? ""
        ]

        var cal = Calendar.current
        cal.timeZone = tz
        let components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id.uuidString, content: content, trigger: trigger)

        Task {
            try? await center.add(request)
        }
    }

    // MARK: — Cancel

    func cancel(id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: — Snooze (called from notification delegate)

    func snooze(id: UUID, tripName: String, title: String) {
        let content = UNMutableNotificationContent()
        content.title              = title
        content.body               = "Snoozed — starting soon."
        content.sound              = .default
        content.interruptionLevel  = .timeSensitive
        content.categoryIdentifier = "DAYTHREAD_EVENT"
        content.userInfo           = ["eventID": id.uuidString]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
        let request = UNNotificationRequest(identifier: "\(id.uuidString)-snooze", content: content, trigger: trigger)
        Task { try? await center.add(request) }
    }

    // MARK: — Private

    private func reminderBody(for event: TripEvent, tripName: String, start: Date, tz: TimeZone) -> String {
        var cal = Calendar.current
        cal.timeZone = tz
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone  = tz
        let timeString = formatter.string(from: start)

        if reminderMinutes < 60 {
            return "\(tripName) · Starts at \(timeString)"
        } else {
            return "\(tripName) · Coming up at \(timeString)"
        }
    }
}
