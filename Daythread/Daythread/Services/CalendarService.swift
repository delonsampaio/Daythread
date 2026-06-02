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

    func sync(_ event: TripEvent, tripName: String, context: NSManagedObjectContext) {
        guard authorized else { return }
        guard let dayDate = event.day?.date else { return }

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
        if let st = event.startTime {
            // startTime stores only the TIME component — the date part reflects
            // whenever the event was created, not the trip day. Combine dayDate
            // (the correct calendar date) with the time from startTime.
            startDate = combining(dayDate: dayDate, time: st, in: startTZ)
            if let et = event.endTime {
                let endOnDay = combining(dayDate: dayDate, time: et, in: startTZ)
                // If end is before start the event crosses midnight — push to next day.
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
