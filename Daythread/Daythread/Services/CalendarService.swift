//
//  CalendarService.swift
//  Daythread
//
//  Syncs TripEvents to Apple Calendar. One EKCalendar per trip
//  ("Daythread: [trip name]"). EKEvent identifiers are stored on
//  TripEvent.ekEventIdentifier (syncable=NO — device-local).
//
//  @MainActor: consistent with the project's MainActor-by-default isolation.
//  EKEventStore operations are synchronous file-system writes — fast enough
//  for main-thread use. This also lets us write ekEventIdentifier directly
//  without context.perform, avoiding TripEvent Sendable/actor-boundary issues.
//

import EventKit
import CoreData
import UIKit

@MainActor
final class CalendarService {
    static let shared = CalendarService()
    private let store = EKEventStore()
    private var authorized = false

    private init() {
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    // MARK: — Authorization

    func ensureAuthorized() async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            authorized = true
        case .notDetermined:
            authorized = (try? await store.requestFullAccessToEvents()) ?? false
        default:
            authorized = false
        }
    }

    // MARK: — Sync (create or update)

    /// Key for the global calendar sync toggle stored in UserDefaults / AppStorage.
    static let globalToggleKey = "daythread.calendarSyncEnabled"

    private var globalSyncEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.globalToggleKey) as? Bool ?? true
    }

    func sync(_ event: TripEvent, tripName: String, context: NSManagedObjectContext) {
        guard authorized, globalSyncEnabled else { return }
        guard let dayDate = event.day?.date else { return }

        // Per-event opt-out: remove from calendar if previously synced, then stop.
        if !event.showInCalendar {
            if !event.ekEventIdentifier.isEmpty {
                remove(identifier: event.ekEventIdentifier)
                event.ekEventIdentifier = ""
                try? context.save()
            }
            return
        }

        // Timezone: transit events use their departure timezone; others use current.
        let startTZ: TimeZone
        if let td = event.transitDetails {
            startTZ = TimeZone(identifier: td.departureTZIdentifier) ?? .current
        } else {
            startTZ = .current
        }

        let isAllDay = event.startTime == nil
        let startDate: Date
        let endDate: Date
        if let start = event.eventStart(in: startTZ) {
            startDate = start
            if let et = event.endTime {
                let endOnDay = combining(dayDate: dayDate, time: et, in: startTZ)
                endDate = endOnDay >= startDate ? endOnDay
                        : Calendar.current.date(byAdding: .day, value: 1, to: endOnDay)!
            } else {
                endDate = Calendar.current.date(byAdding: .hour, value: 1, to: startDate)!
            }
        } else {
            startDate = Calendar.current.startOfDay(for: dayDate)
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        }

        let ekEvent: EKEvent
        if !event.ekEventIdentifier.isEmpty,
           let existing = store.event(withIdentifier: event.ekEventIdentifier) {
            ekEvent = existing
        } else {
            ekEvent = EKEvent(eventStore: store)
            ekEvent.calendar = dayThreadCalendar(for: tripName)
        }

        ekEvent.title    = event.title.isEmpty ? "(Untitled)" : event.title
        ekEvent.startDate = startDate
        ekEvent.endDate  = endDate
        ekEvent.isAllDay = isAllDay
        ekEvent.location = event.location
        ekEvent.notes    = event.notes.isEmpty ? nil : event.notes
        ekEvent.timeZone = startTZ

        // Alarm: fire N minutes before the event. Offset is negative (before start).
        let offsetMinutes = UserDefaults.standard.object(forKey: NotificationService.reminderOffsetKey) as? Int ?? 15
        ekEvent.alarms = isAllDay ? [] : [EKAlarm(relativeOffset: -Double(offsetMinutes * 60))]

        do {
            try store.save(ekEvent, span: .thisEvent, commit: true)
            event.ekEventIdentifier = ekEvent.eventIdentifier ?? ""
            try? context.save()
        } catch {
            print("CalendarService: save failed — \(error.localizedDescription)")
        }
    }

    // MARK: — Remove

    func remove(identifier: String) {
        guard authorized, !identifier.isEmpty else { return }
        guard let event = store.event(withIdentifier: identifier) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
    }

    // MARK: — Helpers

    /// Returns a Date whose calendar date comes from `dayDate` and whose time
    /// components come from `time`, both interpreted in `timezone`.
    private func combining(dayDate: Date, time: Date, in timezone: TimeZone) -> Date {
        var cal = Calendar.current
        cal.timeZone = timezone
        let d = cal.dateComponents([.year, .month, .day], from: dayDate)
        let t = cal.dateComponents([.hour, .minute, .second], from: time)
        var combined = DateComponents()
        combined.year   = d.year;   combined.month  = d.month;  combined.day    = d.day
        combined.hour   = t.hour;   combined.minute = t.minute; combined.second = t.second
        combined.timeZone = timezone
        return cal.date(from: combined) ?? time
    }

    // MARK: — Per-trip calendar

    private func dayThreadCalendar(for tripName: String) -> EKCalendar {
        let title = "Daythread: \(tripName)"
        if let existing = store.calendars(for: .event).first(where: { $0.title == title }) {
            return existing
        }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title   = title
        cal.cgColor = UIColor.systemBlue.cgColor
        cal.source  = store.defaultCalendarForNewEvents?.source
        try? store.saveCalendar(cal, commit: true)
        return cal
    }
}
