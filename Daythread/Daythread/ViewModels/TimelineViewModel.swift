//
//  TimelineViewModel.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import Foundation
import SwiftData
import Observation

@Observable
final class TimelineViewModel {
    // Derived state refreshed via .onChange(of: days) in TimelineView
    var activeLodging: LodgingInfo?
    var runningLateMode: Bool = false
    // Tier 2 — ETAEngine results keyed by event ID
    var etaMap: [UUID: Duration] = [:]

    // MARK: — Refresh (called from .onChange in the view)

    func refresh(days: [TripDay], lodging: [LodgingInfo]) {
        let today = Calendar.current.startOfDay(for: Date())
        activeLodging = lodging.first {
            Calendar.current.startOfDay(for: $0.checkIn) <= today &&
            today <= Calendar.current.startOfDay(for: $0.checkOut)
        }
    }

    // MARK: — Writes (all go through the view's ModelContext)

    func moveEvent(
        _ event: TripEvent,
        toDay day: TripDay,
        newSortOrder: Int,
        context: ModelContext
    ) {
        event.day = day
        event.sortOrder = newSortOrder
        try? context.save()
    }

    func deleteEvent(_ event: TripEvent, context: ModelContext) {
        context.delete(event)
        try? context.save()
    }

    func lockEvent(_ event: TripEvent, context: ModelContext) {
        event.isTimeLocked.toggle()
        try? context.save()
    }
}
