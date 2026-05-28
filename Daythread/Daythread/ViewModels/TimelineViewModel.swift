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

    func moveEvent(
        _ event: TripEvent,
        toDay day: TripDay,
        newSortOrder: Int,
        context: ModelContext
    ) {
        guard !event.isTimeLocked else { return }
        event.day = day
        event.sortOrder = newSortOrder
        try? context.save()
    }

    /// Inserts the dragged event immediately before `targetEvent` in `targetDay`.
    /// Works across days. Returns `false` (and fires a warning haptic) if the
    /// resulting order would violate any time-locked event's chronological position.
    /// Returns `false` silently if the event is already locked or the ID is invalid.
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

        // Build the proposed new order for the target day.
        var proposed = (targetDay.events ?? [])
            .filter { $0.id != dragged.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        let insertAt = proposed.firstIndex(where: { $0.id == targetEvent.id }) ?? proposed.endIndex
        proposed.insert(dragged, at: insertAt)

        // Reject the move if it would push a locked event out of time sequence.
        if isLockOrderViolated(in: proposed) {
            shakeViolators(in: proposed)
            HapticManager.shared.deleteAction()
            return false
        }

        dragged.day = targetDay

        // Fractional indexing: compute a sortOrder only for the dragged event.
        // This writes exactly ONE record to CloudKit per drag instead of updating
        // every event in the day. The source day needs no renumbering — removing
        // an item preserves the relative order of the remaining events.
        let predOrder: Int? = insertAt > 0 ? proposed[insertAt - 1].sortOrder : nil
        let succOrder: Int? = (insertAt + 1) < proposed.count ? proposed[insertAt + 1].sortOrder : nil

        if let newOrder = midOrder(pred: predOrder, succ: succOrder) {
            dragged.sortOrder = newOrder
        } else {
            // Integer gap exhausted — full renumber with 1024 spacing.
            for (i, e) in proposed.enumerated() { e.sortOrder = i * 1024 }
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

        // Fractional: append at predecessor + 1024 — one record write.
        // Source day needs no renumbering (relative order of remaining events is unchanged).
        let predOrder = proposed.count > 1 ? proposed[proposed.count - 2].sortOrder : nil
        dragged.sortOrder = (predOrder ?? 0) + 1024

        try? context.save()
        return true
    }

    // MARK: — Private helpers

    /// Sets `shakingEventIDs` to the locked events violated in `proposed`, then
    /// clears it after 600 ms so the shake animation completes before resetting.
    private func shakeViolators(in proposed: [TripEvent]) {
        let violators = violatedLockIDs(in: proposed)
        shakingEventIDs = violators
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            shakingEventIDs = []
        }
    }

    /// Fractional indexing: returns a sortOrder value for an item placed between
    /// `pred` and `succ`. Returns `nil` when the integer gap is exhausted
    /// (mid == pred), signalling the caller to fall back to a full renumber.
    ///
    /// Initial spacing of 1024 means ~10 consecutive inserts in the same gap
    /// before a rebalance is needed — well beyond any realistic trip itinerary.
    private func midOrder(pred: Int?, succ: Int?) -> Int? {
        switch (pred, succ) {
        case (nil, nil):      return 1024
        case (nil, let s?):   return s > 1 ? s / 2 : nil
        case (let p?, nil):   return p + 1024
        case (let p?, let s?):
            let mid = (p + s) / 2
            return mid > p ? mid : nil   // nil = gap exhausted
        }
    }

    private func fetchEvent(id: UUID, context: ModelContext) -> TripEvent? {
        let descriptor = FetchDescriptor<TripEvent>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// Returns true if placing events in this order would put any time-locked
    /// event's `startTime` out of chronological sequence with its timed neighbors.
    /// Events without a `startTime` are skipped — only timed events can trigger
    /// or satisfy a violation.
    func isLockOrderViolated(in events: [TripEvent]) -> Bool {
        for (i, event) in events.enumerated() {
            guard event.isTimeLocked, let lockedTime = event.startTime else { continue }
            // A timed event before this locked event must not be later.
            if i > 0, let prevTime = events[i - 1].startTime, prevTime > lockedTime {
                return true
            }
            // A timed event after this locked event must not be earlier.
            if i < events.count - 1, let nextTime = events[i + 1].startTime, nextTime < lockedTime {
                return true
            }
        }
        return false
    }

    /// Returns the IDs of locked events that are currently out of chronological
    /// order with their timed neighbours. Used by the view to show warning badges.
    func violatedLockIDs(in events: [TripEvent]) -> Set<UUID> {
        var violated = Set<UUID>()
        for (i, event) in events.enumerated() {
            guard event.isTimeLocked, let lockedTime = event.startTime else { continue }
            if i > 0, let prevTime = events[i - 1].startTime, prevTime > lockedTime {
                violated.insert(event.id)
            }
            if i < events.count - 1, let nextTime = events[i + 1].startTime, nextTime < lockedTime {
                violated.insert(event.id)
            }
        }
        return violated
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
