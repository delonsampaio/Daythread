//
//  CalendarService.swift
//  Daythread
//
//  Syncs TripEvents to Apple Calendar. One EKCalendar per trip
//  ("Daythread: [trip name]"). EKEvent identifiers are stored on
//  TripEvent.ekEventIdentifier (syncable=NO — device-local).
//
//  Authorization: requested lazily on first sync, never nagged again.
//  If the user denies, syncs silently no-op. Requires iOS 17+ full-access
//  API (deployment target is iOS 26.5).
//

import EventKit
import CoreData
import UIKit

final class CalendarService {
    static let shared = CalendarService()
    private let store = EKEventStore()
    private var authorized = false

    private init() {
        // Reflect existing permission without prompting.
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    // MARK: — Authorization

    /// Requests full calendar access if not yet determined. Safe to call repeatedly —
    /// subsequent calls are a fast status check with no UI.
    func ensureAuthorized() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            authorized = true
        case .notDetermined:
            authorized = (try? await store.requestFullAccessToEvents()) ?? false
        default:
            authorized = false
        }
    }

    // MARK: — Sync (create or update)

    /// Creates or updates the EKEvent for `event`. Writes the EKEvent identifier
    /// back to `event.ekEventIdentifier` via `context.perform` so the caller can
    /// treat this as fire-and-forget.
    func sync(_ event: TripEvent, tripName: String, context: NSManagedObjectContext) {
        guard authorized else { return }
        guard let dayDate = event.day?.date else { return }

        // Start / end dates: use startTime when set; fall back to all-day on the day's date.
        let isAllDay = event.startTime == nil
        let startDate: Date
        let endDate: Date
        if let st = event.startTime {
            startDate = st
            endDate = event.endTime ?? Calendar.current.date(byAdding: .hour, value: 1, to: st)!
        } else {
            startDate = Calendar.current.startOfDay(for: dayDate)
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        }

        // Timezone: transit events use their departure timezone; others use current.
        let startTZ: TimeZone
        if let td = event.transitDetails {
            startTZ = TimeZone(identifier: td.departureTZIdentifier) ?? .current
        } else {
            startTZ = .current
        }

        // Find or create the EKEvent.
        let ekEvent: EKEvent
        if !event.ekEventIdentifier.isEmpty,
           let existing = store.event(withIdentifier: event.ekEventIdentifier) {
            ekEvent = existing
        } else {
            ekEvent = EKEvent(eventStore: store)
            ekEvent.calendar = dayThreadCalendar(for: tripName)
        }

        ekEvent.title       = event.title.isEmpty ? "(Untitled)" : event.title
        ekEvent.startDate   = startDate
        ekEvent.endDate     = endDate
        ekEvent.isAllDay    = isAllDay
        ekEvent.location    = event.location
        ekEvent.notes       = event.notes.isEmpty ? nil : event.notes
        ekEvent.timeZone = startTZ

        do {
            try store.save(ekEvent, span: .thisEvent, commit: true)
            let identifier = ekEvent.eventIdentifier ?? ""
            context.perform {
                event.ekEventIdentifier = identifier
                try? context.save()
            }
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

    // MARK: — Per-trip calendar

    private func dayThreadCalendar(for tripName: String) -> EKCalendar {
        let title = "Daythread: \(tripName)"
        if let existing = store.calendars(for: .event).first(where: { $0.title == title }) {
            return existing
        }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title  = title
        cal.cgColor = UIColor.systemBlue.cgColor
        cal.source  = store.defaultCalendarForNewEvents?.source
        try? store.saveCalendar(cal, commit: true)
        return cal
    }
}
