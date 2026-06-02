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

        let startTZ: TimeZone
        if let td = event.transitDetails {
            startTZ = TimeZone(identifier: td.departureTZIdentifier) ?? .current
        } else {
            startTZ = .current
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
