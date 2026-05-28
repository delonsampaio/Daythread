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
    /// IDs of locked events currently shaking because a drop violated their constraint.
    /// Populated for ~600 ms after a refused drop, then cleared automatically.
    var shakingEventIDs: Set<UUID> = []

    // MARK: — Refresh (called from .onChange in the view)

    func refresh(days: [TripDay], lodging: [LodgingInfo]) {
        let today = Calendar.current.startOfDay(for: Date())
        activeLodging = lodging.first {
            Calendar.current.startOfDay(for: $0.checkIn) <= today &&
            today <= Calendar.current.startOfDay(for: $0.checkOut)
        }
    }

    // MARK: — Writes (all go through the view's ModelContext)

    /// Inserts the dragged event immediately before `targetEvent` in `targetDay`.
    /// Works across days. Returns `false` (and fires a warning haptic) if the
    /// resulting order would violate any time-locked event's chronological position.
    @discardableResult
    func reorderEvent(
        draggedID: String,
        before targetEvent: TripEvent,
        in targetDay: TripDay,
        context: ModelContext
    ) -> Bool {
        guard let uuid = UUID(uuidString: draggedID) else { return false }
        guard let dragged = fetchEvent(id: uuid, context: context) else { return false }
        guard !dragged.isTimeLocked else { return false }

        let sourceDay = dragged.day

        var proposed = (targetDay.events ?? [])
            .filter { $0.id != dragged.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        let insertAt = proposed.firstIndex(where: { $0.id == targetEvent.id }) ?? proposed.endIndex
        proposed.insert(dragged, at: insertAt)

        if isLockOrderViolated(in: proposed) {
            shakeViolators(in: proposed)
            HapticManager.shared.deleteAction()
            return false
        }

        dragged.day = targetDay
        for (i, e) in proposed.enumerated() { e.sortOrder = i }

        if let sourceDay, sourceDay.id != targetDay.id {
            let remaining = (sourceDay.events ?? [])
                .filter { $0.id != dragged.id }
                .sorted { $0.sortOrder < $1.sortOrder }
            for (i, e) in remaining.enumerated() { e.sortOrder = i }
        }

        try? context.save()
        return true
    }

    /// Appends the dragged event to the end of `targetDay`. Works across days.
    /// Returns `false` (and fires a warning haptic) if appending would violate a
    /// locked event's chronological position.
    @discardableResult
    func appendEvent(draggedID: String, to targetDay: TripDay, context: ModelContext) -> Bool {
        guard let uuid = UUID(uuidString: draggedID) else { return false }
        guard let dragged = fetchEvent(id: uuid, context: context) else { return false }
        guard !dragged.isTimeLocked else { return false }

        let sourceDay = dragged.day

        var proposed = (targetDay.events ?? [])
            .filter { $0.id != dragged.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        proposed.append(dragged)

        if isLockOrderViolated(in: proposed) {
            shakeViolators(in: proposed)
            HapticManager.shared.deleteAction()
            return false
        }

        dragged.day = targetDay
        for (i, e) in proposed.enumerated() { e.sortOrder = i }

        if let sourceDay, sourceDay.id != targetDay.id {
            let remaining = (sourceDay.events ?? [])
                .filter { $0.id != dragged.id }
                .sorted { $0.sortOrder < $1.sortOrder }
            for (i, e) in remaining.enumerated() { e.sortOrder = i }
        }

        try? context.save()
        return true
    }

    func deleteEvent(_ event: TripEvent, context: ModelContext) {
        context.delete(event)
        try? context.save()
    }

    func lockEvent(_ event: TripEvent, context: ModelContext) {
        event.isTimeLocked.toggle()
        try? context.save()
    }

    // MARK: — Lock-order helpers

    /// Returns true if placing events in this order would put any time-locked
    /// event's `startTime` out of chronological sequence with its timed neighbors.
    func isLockOrderViolated(in events: [TripEvent]) -> Bool {
        for (i, event) in events.enumerated() {
            guard event.isTimeLocked, let lockedTime = event.startTime else { continue }
            if i > 0, let prevTime = events[i - 1].startTime, prevTime > lockedTime { return true }
            if i < events.count - 1, let nextTime = events[i + 1].startTime, nextTime < lockedTime { return true }
        }
        return false
    }

    /// Returns the IDs of locked events that are currently out of chronological
    /// order with their timed neighbours. Used by the view to show warning badges.
    func violatedLockIDs(in events: [TripEvent]) -> Set<UUID> {
        var violated = Set<UUID>()
        for (i, event) in events.enumerated() {
            guard event.isTimeLocked, let lockedTime = event.startTime else { continue }
            if i > 0, let prevTime = events[i - 1].startTime, prevTime > lockedTime { violated.insert(event.id) }
            if i < events.count - 1, let nextTime = events[i + 1].startTime, nextTime < lockedTime { violated.insert(event.id) }
        }
        return violated
    }

    // MARK: — Private helpers

    /// Sets `shakingEventIDs` to the locked events violated in `proposed`, then
    /// clears it after 600 ms so the shake animation completes before resetting.
    private func shakeViolators(in proposed: [TripEvent]) {
        shakingEventIDs = violatedLockIDs(in: proposed)
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            shakingEventIDs = []
        }
    }

    private func fetchEvent(id: UUID, context: ModelContext) -> TripEvent? {
        let descriptor = FetchDescriptor<TripEvent>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }
}
