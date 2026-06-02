//
//  TimelineViewModel.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import Foundation
import CoreData
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
    /// In-flight event deletion driving the screen-level undo toast. Lives here
    /// (not in a day section) so the toast pins to the screen, not the deleted row.
    var pendingEventDelete: PendingDelete?

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
        context: NSManagedObjectContext,
        currentUserID: String? = nil
    ) {
        guard !event.isTimeLocked else { return }
        let conflictIDs = conflictingIDs(event, in: day, visibleTo: currentUserID)
        if !conflictIDs.isEmpty {
            shakeEvents(conflictIDs)
            HapticManager.shared.deleteAction()
            return
        }
        event.day = day
        event.sortOrder = newSortOrder
        try? context.save()
        syncCalendar(event, context: context)
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
        context: NSManagedObjectContext,
        currentUserID: String? = nil
    ) -> Bool {
        guard let uuid = UUID(uuidString: draggedID) else { return false }
        guard let dragged = fetchEvent(id: uuid, context: context) else { return false }
        guard !dragged.isTimeLocked else { return false }

        // Build the proposed new order for the target day.
        var proposed = targetDay.eventsArray
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

        // Reject if the dragged event's time overlaps with an existing VISIBLE event in the target day.
        // Hidden private events are excluded so co-editors can't infer their existence from a silent rejection.
        let timeConflictIDs = conflictingIDs(dragged, in: targetDay, visibleTo: currentUserID)
        if !timeConflictIDs.isEmpty {
            shakeEvents(timeConflictIDs)
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
        syncCalendar(dragged, context: context)
        return true
    }

    /// Appends the dragged event to the end of `targetDay`. Works across days.
    /// Returns `false` (and fires a warning haptic) if appending would violate a
    /// locked event's chronological position.
    @discardableResult
    func appendEvent(draggedID: String, to targetDay: TripDay, context: NSManagedObjectContext, currentUserID: String? = nil) -> Bool {
        guard let uuid = UUID(uuidString: draggedID) else { return false }
        guard let dragged = fetchEvent(id: uuid, context: context) else { return false }
        guard !dragged.isTimeLocked else { return false }

        var proposed = targetDay.eventsArray
            .filter { $0.id != dragged.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        proposed.append(dragged)

        if isLockOrderViolated(in: proposed) {
            shakeViolators(in: proposed)
            HapticManager.shared.deleteAction()
            return false
        }

        let timeConflictIDs = conflictingIDs(dragged, in: targetDay, visibleTo: currentUserID)
        if !timeConflictIDs.isEmpty {
            shakeEvents(timeConflictIDs)
            HapticManager.shared.deleteAction()
            return false
        }

        dragged.day = targetDay

        // Fractional: append at predecessor + 1024 — one record write.
        // Source day needs no renumbering (relative order of remaining events is unchanged).
        let predOrder = proposed.count > 1 ? proposed[proposed.count - 2].sortOrder : nil
        dragged.sortOrder = (predOrder ?? 0) + 1024

        try? context.save()
        syncCalendar(dragged, context: context)
        return true
    }

    // MARK: — Private helpers

    /// Shakes the given event IDs for 600 ms then clears.
    private func shakeEvents(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        shakingEventIDs = ids
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            shakingEventIDs = []
        }
    }

    private func shakeViolators(in proposed: [TripEvent]) {
        shakeEvents(violatedLockIDs(in: proposed))
    }

    /// Returns IDs of events in `day` whose time window conflicts with `event`.
    /// When `userID` is provided and the trip is shared, hidden private events are excluded
    /// so co-editors cannot infer the existence of events they are not allowed to see.
    private func conflictingIDs(_ event: TripEvent, in day: TripDay, visibleTo userID: String? = nil) -> Set<UUID> {
        guard let start = event.startTime, let end = event.endTime else { return [] }
        let candidates: [TripEvent]
        if let userID, !userID.isEmpty, day.trip?.cloudKitShareID != nil {
            candidates = day.eventsArray.filter { e in
                guard e.isPrivate else { return true }
                if e.addedByAppleUserID == userID { return true }
                guard !e.visibleToMemberIDs.isEmpty else { return false }
                return e.visibleToMemberIDs.split(separator: ",").contains(userID[...])
            }
        } else {
            candidates = day.eventsArray
        }
        return Set(ScheduleEngine.findConflicts(
            startTime: start,
            endTime: end,
            among: candidates,
            excludingID: event.id
        ).compactMap(\.id))
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

    private func fetchEvent(id: UUID, context: NSManagedObjectContext) -> TripEvent? {
        let request = TripEvent.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Returns true if placing events in this order would put any time-locked
    /// event's `startTime` out of chronological sequence with its timed neighbors.
    /// Untimed events are transparent — the check looks through them to find the
    /// nearest timed event in each direction, so an untimed event between B(8:30pm)
    /// and locked A(8pm) does not hide the violation.
    /// Returns true if placing events in this order would put any time-locked
    /// event out of chronological sequence with any of its timed neighbours —
    /// not just the nearest one.
    ///
    /// Checking only the nearest timed predecessor/successor misses cases like
    ///   [B(10pm), Y(6pm), A(8pm, locked)]
    /// where Y(6pm) is the nearest predecessor of A and passes the check, but
    /// B(10pm) further back also precedes A and violates its position.
    /// Fix: scan ALL timed events on each side with `contains(where:)`.
    func isLockOrderViolated(in events: [TripEvent]) -> Bool {
        for (i, event) in events.enumerated() {
            guard event.isTimeLocked, let lockedTime = event.startTime else { continue }
            // Any timed event BEFORE this locked event must not be later.
            if events[..<i].compactMap(\.startTime).contains(where: { $0 > lockedTime }) {
                return true
            }
            // Any timed event AFTER this locked event must not be earlier.
            if events[(i + 1)...].compactMap(\.startTime).contains(where: { $0 < lockedTime }) {
                return true
            }
        }
        return false
    }

    /// Returns the IDs of locked events that are currently out of chronological
    /// order with any of their timed neighbours. Used by the view to show warning badges.
    func violatedLockIDs(in events: [TripEvent]) -> Set<UUID> {
        var violated = Set<UUID>()
        for (i, event) in events.enumerated() {
            guard event.isTimeLocked, let lockedTime = event.startTime else { continue }
            guard let id = event.id else { continue }
            if events[..<i].compactMap(\.startTime).contains(where: { $0 > lockedTime }) {
                violated.insert(id)
            }
            if events[(i + 1)...].compactMap(\.startTime).contains(where: { $0 < lockedTime }) {
                violated.insert(id)
            }
        }
        return violated
    }

    // MARK: — Chronological order

    /// Returns IDs of unlocked, timed events whose visual `sortOrder` position
    /// contradicts their `startTime` relative to any other timed event in the list.
    ///
    /// Locked events are intentionally excluded — `violatedLockIDs` already surfaces
    /// them with the full amber ring + badge treatment. This function targets the
    /// softer case: the user dragged an unlocked event out of time order while
    /// drafting, and the UI should note it passively (amber time text only).
    func outOfOrderEventIDs(in events: [TripEvent]) -> Set<UUID> {
        var outOfOrder = Set<UUID>()
        for (i, event) in events.enumerated() {
            guard !event.isTimeLocked, let eventTime = event.startTime, let id = event.id else { continue }
            // Flagged if any earlier-positioned event has a later startTime.
            if events[..<i].compactMap(\.startTime).contains(where: { $0 > eventTime }) {
                outOfOrder.insert(id)
            }
            // Flagged if any later-positioned event has an earlier startTime.
            if events[(i + 1)...].compactMap(\.startTime).contains(where: { $0 < eventTime }) {
                outOfOrder.insert(id)
            }
        }
        return outOfOrder
    }

    /// Re-sorts a day's events so untimed events float to the top (preserving their
    /// relative order) and timed events follow in strict chronological order.
    /// Uses 1024-spaced sortOrders for fractional-indexing compatibility.
    func sortDayByTime(_ day: TripDay, context: NSManagedObjectContext) {
        let sorted = day.eventsArray.sorted { a, b in
            switch (a.startTime, b.startTime) {
            case (nil, nil):           return a.sortOrder < b.sortOrder  // preserve untimed order
            case (nil, _):             return true                        // untimed floats up
            case (_, nil):             return false                       // timed sinks below
            case (let ta?, let tb?):   return ta < tb                    // chronological
            }
        }
        for (i, event) in sorted.enumerated() {
            event.sortOrder = i * 1024
        }
        try? context.save()
        HapticManager.shared.sheetConfirm()
    }

    private func syncCalendar(_ event: TripEvent, context: NSManagedObjectContext) {
        let tripName = event.day?.trip?.name ?? ""
        CalendarService.shared.sync(event, tripName: tripName, context: context)
        NotificationService.shared.schedule(event)
    }

    func deleteEvent(_ event: TripEvent, context: NSManagedObjectContext) {
        let ekID = event.ekEventIdentifier
        let eventID = event.id
        context.delete(event)
        try? context.save()
        if !ekID.isEmpty {
            CalendarService.shared.remove(identifier: ekID)
        }
        if let id = eventID {
            NotificationService.shared.cancel(id: id)
        }
    }

    func lockEvent(_ event: TripEvent, context: NSManagedObjectContext) {
        event.isTimeLocked.toggle()
        try? context.save()
    }
}
