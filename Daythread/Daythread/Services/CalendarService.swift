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

    // Authorization is never cached — checking the live status is cheap and
    // prevents a stale true after the user revokes permission in iOS Settings.
    private var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    private init() {}

    // MARK: — Authorization

    func ensureAuthorized() async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            break   // already granted — no prompt needed
        case .notDetermined:
            _ = try? await store.requestFullAccessToEvents()
        default:
            break   // denied/restricted — sync calls will no-op via isAuthorized
        }
    }

    // MARK: — Sync (create or update)

    static let globalToggleKey = "daythread.calendarSyncEnabled"

    private var globalSyncEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.globalToggleKey) as? Bool ?? true
    }

    func sync(_ event: TripEvent, tripName: String, context: NSManagedObjectContext) {
        guard isAuthorized, globalSyncEnabled else { return }
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
            // Use the shared eventEnd(in:) helper — handles date-combining and
            // overnight crossing in one place (DRY with eventStart).
            endDate = event.eventEnd(in: startTZ)
                   ?? Calendar.current.date(byAdding: .hour, value: 1, to: startDate)!
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

        // Alarm: only attach when the user chose "calendar" or "both" AND the
        // event-level reminder toggle is on.
        if !isAllDay && event.hasReminder && NotificationService.shared.calendarAlarmsActive {
            let offsetMinutes = UserDefaults.standard.object(forKey: NotificationService.reminderOffsetKey) as? Int ?? 15
            ekEvent.alarms = [EKAlarm(relativeOffset: -Double(offsetMinutes * 60))]
        } else {
            ekEvent.alarms = []
        }

        do {
            try store.save(ekEvent, span: .thisEvent, commit: true)
            // Persist the EKEvent identifier so future edits/deletes can find it.
            // A second context.save() here is intentional — we can't return the
            // identifier to the caller without making sync() async/throwing.
            event.ekEventIdentifier = ekEvent.eventIdentifier ?? ""
            try? context.save()
        } catch {
            print("CalendarService: save failed — \(error.localizedDescription)")
        }
    }

    // MARK: — Remove

    func remove(identifier: String) {
        guard isAuthorized, !identifier.isEmpty else { return }
        guard let event = store.event(withIdentifier: identifier) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
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
