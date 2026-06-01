//
//  TimelineViewModelTests.swift
//  DaythreadTests
//
//  Created by Delon Sampaio on 5/27/26.
//
//  Tests for TimelineViewModel drag-and-drop reordering logic.
//  Uses an in-memory container so saves are synchronous and tests
//  complete in well under 1 second.
//

import XCTest
import CoreData
@testable import Daythread

@MainActor
final class TimelineViewModelTests: XCTestCase {

    // MARK: — Helpers

    private var ctx: NSManagedObjectContext {
        PersistenceController(inMemory: true).viewContext
    }

    /// Sets up a trip with one day and the given event titles (sortOrder assigned 0, 1, 2…).
    private func makeDay(
        eventTitles: [String],
        context: NSManagedObjectContext
    ) -> (TripDay, [TripEvent]) {
        let trip = Trip(context: context)
        trip.id = UUID()
        trip.name = "Test"
        trip.destination = "Anywhere"
        trip.startDate = .now
        trip.endDate = .now

        let day = TripDay(context: context)
        day.id = UUID()
        day.date = .now
        day.sortOrder = 0
        day.trip = trip

        let events: [TripEvent] = eventTitles.enumerated().map { i, title in
            let e = TripEvent(context: context)
            e.id = UUID()
            e.title = title
            e.category = .activity
            e.sortOrder = i
            e.day = day
            return e
        }
        try? context.save()
        return (day, events)
    }

    // MARK: — reorderEvent

    /// Dragging the last event to before the first event makes it first.
    func testReorderMakesLastEventFirst() throws {
        let context = ctx
        let vm = TimelineViewModel()

        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        // events[2] = "C" (sortOrder 2), drop before events[0] = "A"

        vm.reorderEvent(draggedID: events[2].id!.uuidString,
                        before: events[0],
                        in: day,
                        context: context)

        let reordered = day.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(reordered.map(\.title), ["C", "A", "B"])
    }

    /// Dragging the first event to before the last event gives [B, A, C].
    func testReorderMovesFirstToSecondToLast() throws {
        let context = ctx
        let vm = TimelineViewModel()

        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        // events[0] = "A", drop before events[2] = "C" → [B, A, C]

        vm.reorderEvent(draggedID: events[0].id!.uuidString,
                        before: events[2],
                        in: day,
                        context: context)

        let reordered = day.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(reordered.map(\.title), ["B", "A", "C"])
    }

    /// When the integer gap is exhausted (succ == 0, can't place before it),
    /// reorderEvent falls back to a full renumber using 1024 spacing.
    /// Dragging C(sortOrder 2) before A(sortOrder 0): midOrder(pred:nil, succ:0)
    /// returns nil → renumber → [0, 1024, 2048].
    func testReorderRenumbersWithFractionalSpacingWhenGapExhausted() throws {
        let context = ctx
        let vm = TimelineViewModel()

        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)

        vm.reorderEvent(draggedID: events[2].id!.uuidString,
                        before: events[0],
                        in: day,
                        context: context)

        let reordered = day.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(reordered.map(\.sortOrder), [0, 1024, 2048])
    }

    /// A time-locked event cannot be dragged — reorderEvent is a no-op for it.
    func testReorderIgnoresTimeLocked() throws {
        let context = ctx
        let vm = TimelineViewModel()

        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        events[2].isTimeLocked = true
        try context.save()

        vm.reorderEvent(draggedID: events[2].id!.uuidString,
                        before: events[0],
                        in: day,
                        context: context)

        // Order must remain unchanged
        let reordered = day.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(reordered.map(\.title), ["A", "B", "C"])
    }

    /// An invalid UUID string (e.g. empty) is silently ignored.
    func testReorderWithInvalidIDIsNoop() throws {
        let context = ctx
        let vm = TimelineViewModel()

        let (day, events) = makeDay(eventTitles: ["A", "B"], context: context)

        vm.reorderEvent(draggedID: "not-a-uuid",
                        before: events[0],
                        in: day,
                        context: context)

        let reordered = day.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(reordered.map(\.title), ["A", "B"])
    }

    // MARK: — appendEvent

    /// Dragging the first event to the end moves it last.
    func testAppendMovesFirstToEnd() throws {
        let context = ctx
        let vm = TimelineViewModel()

        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)

        vm.appendEvent(draggedID: events[0].id!.uuidString, to: day, context: context)

        let reordered = day.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(reordered.map(\.title), ["B", "C", "A"])
    }

    // MARK: — Lock-order conflict

    /// Helper: assigns a same-day Date at the given hour (and optional minute) to event.startTime.
    private func setTime(_ event: TripEvent, hour: Int, minute: Int = 0, context: NSManagedObjectContext) {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour; c.minute = minute
        event.startTime = Calendar.current.date(from: c)!
    }

    /// Dragging an event to a position that would put a LOCKED event out of
    /// chronological order must be refused (returns false, order unchanged).
    func testReorderRefusesDropViolatingLockedEvent() throws {
        let context = ctx
        let vm = TimelineViewModel()

        // [A(9am), B(10am, locked), C(11am)]
        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        setTime(events[0], hour: 9, context: context)
        setTime(events[1], hour: 10, context: context); events[1].isTimeLocked = true
        setTime(events[2], hour: 11, context: context)
        try context.save()

        // Drag C(11am) before B(10am, locked) → [A, C(11am), B(10am, locked)]
        // B(locked,10am) would have C(11am) immediately before it → violation.
        let moved = vm.reorderEvent(draggedID: events[2].id!.uuidString,
                                    before: events[1], in: day, context: context)

        XCTAssertFalse(moved, "Drop must be refused: would put a 11am event before a locked 10am event")
        let order = day.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(order.map(\.title), ["A", "B", "C"], "Order must be unchanged after refused drop")
    }

    /// A drop that respects all locked events is allowed normally.
    func testReorderAllowsDropThatRespectsLockedOrder() throws {
        let context = ctx
        let vm = TimelineViewModel()

        // [A(9am, locked), B(10am), C(11am)]
        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        setTime(events[0], hour: 9, context: context); events[0].isTimeLocked = true
        setTime(events[1], hour: 10, context: context)
        setTime(events[2], hour: 11, context: context)
        try context.save()

        // Drag C(11am) before B(10am) → [A(9am, locked), C(11am), B(10am)]
        // A stays first, and next event C(11am) > A(9am) → no violation.
        let moved = vm.reorderEvent(draggedID: events[2].id!.uuidString,
                                    before: events[1], in: day, context: context)

        XCTAssertTrue(moved, "Drop should be allowed: locked event A is still in correct time order")
        let order = day.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(order.map(\.title), ["A", "C", "B"])
    }

    /// Events without a startTime are skipped in the lock check — only timed
    /// neighbors can trigger a violation.
    func testReorderIgnoresUntimedNeighborsInLockCheck() throws {
        let context = ctx
        let vm = TimelineViewModel()

        // [A(no time), B(10am, locked), C(no time)]
        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        setTime(events[1], hour: 10, context: context); events[1].isTimeLocked = true
        try context.save()

        // Drag C before A → [C, A, B(10am, locked)]
        // B has no timed neighbors → no violation, move allowed.
        let moved = vm.reorderEvent(draggedID: events[2].id!.uuidString,
                                    before: events[0], in: day, context: context)

        XCTAssertTrue(moved)
        let order = day.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(order.map(\.title), ["C", "A", "B"])
    }

    /// Regression: dragging B(8:30pm) before an untimed C when locked A(8pm) sits
    /// between C and B must be refused. The untimed C masked the violation because
    /// the old check only looked at the immediate neighbor, not the nearest timed one.
    func testReorderRefusesWhenViolationIsHiddenByUntimedGap() throws {
        let context = ctx
        let vm = TimelineViewModel()

        // Order: [C(no time), A(8pm, locked), B(8:30pm)]
        let (day, events) = makeDay(eventTitles: ["C", "A", "B"], context: context)
        // events[0] = C — no startTime set
        setTime(events[1], hour: 20, minute: 0,  context: context); events[1].isTimeLocked = true
        setTime(events[2], hour: 20, minute: 30, context: context)
        try context.save()

        // Drag B(8:30pm) before C → proposed [B(8:30pm), C(no time), A(8pm, locked)]
        // Nearest timed predecessor of A = B(8:30pm) > A(8pm) → should be REFUSED
        let moved = vm.reorderEvent(draggedID: events[2].id!.uuidString,
                                    before: events[0], in: day, context: context)

        XCTAssertFalse(moved, "Drop must be refused: B(8:30pm) is the nearest timed predecessor of locked A(8pm)")
        let order = day.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(order.map(\.title), ["C", "A", "B"], "Order must be unchanged")
    }

    /// Regression: B(10pm) is dragged before Y(6pm), which sits immediately before
    /// locked A(8pm). The OLD check found Y(6pm) as the nearest timed predecessor
    /// and passed (6pm ≤ 8pm). B(10pm) further back was never examined, so the
    /// drop was wrongly allowed. The fix checks ALL timed predecessors/successors.
    func testReorderRefusesWhenNonAdjacentTimedPredecessorViolatesLock() throws {
        let context = ctx
        let vm = TimelineViewModel()

        // Order: [Y(6pm), A(8pm, locked), B(10pm)]
        let (day, events) = makeDay(eventTitles: ["Y", "A", "B"], context: context)
        setTime(events[0], hour: 18, context: context)               // Y = 6 pm
        setTime(events[1], hour: 20, context: context); events[1].isTimeLocked = true  // A = 8 pm, locked
        setTime(events[2], hour: 22, context: context)               // B = 10 pm
        try context.save()

        // Drag B(10pm) before Y(6pm) → proposed [B(10pm), Y(6pm), A(8pm, locked)]
        // Nearest timed pred of A = Y(6pm) ≤ 8pm → old code passes.
        // B(10pm) is also before A → 10pm > 8pm → must be REFUSED.
        let moved = vm.reorderEvent(draggedID: events[2].id!.uuidString,
                                    before: events[0], in: day, context: context)

        XCTAssertFalse(moved, "Drop must be refused: B(10pm) precedes locked A(8pm) even though nearest pred Y(6pm) is valid")
        let order = day.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(order.map(\.title), ["Y", "A", "B"], "Order must be unchanged")
    }

    /// appendEvent is refused when the proposed order would put a timed event
    /// before or after a locked event in a way that violates chronological order —
    /// regardless of whether an intervening untimed event "hides" the gap.
    func testAppendRefusesWhenViolatesLockedEvent() throws {
        let context = ctx
        let vm = TimelineViewModel()

        // Case 1: locked predecessor — appending an 8am event after a locked 9am event.
        // Day: [A(9am, locked), B(11am)]
        // Append Early(8am) → proposed [A(9am, locked), B(11am), Early(8am)]
        // A(locked, 9am): ALL events after A include Early(8am) < 9am → violation.
        let (day, events) = makeDay(eventTitles: ["A", "B"], context: context)
        setTime(events[0], hour: 9, context: context); events[0].isTimeLocked = true
        setTime(events[1], hour: 11, context: context)
        let early = TripEvent(context: context)
        early.id = UUID()
        early.title = "Early"
        early.category = .activity
        early.sortOrder = 2
        early.day = day
        setTime(early, hour: 8, context: context)
        try context.save()

        let moved = vm.appendEvent(draggedID: early.id!.uuidString, to: day, context: context)
        XCTAssertFalse(moved, "Appending Early(8am) after locked A(9am) must be refused")

        // Case 2: locked event at the end — appending an event before it in time.
        // Day: [X(9am), Y(11am, locked)]
        // Append X(9am) to end → proposed [Y(11am, locked), X(9am)]
        // Y(locked, 11am): X(9am) follows Y in sequence but 9am < 11am → violation.
        let (day2, events2) = makeDay(eventTitles: ["X", "Y"], context: context)
        setTime(events2[0], hour: 9, context: context)
        setTime(events2[1], hour: 11, context: context); events2[1].isTimeLocked = true
        try context.save()

        let moved2 = vm.appendEvent(draggedID: events2[0].id!.uuidString, to: day2, context: context)
        XCTAssertFalse(moved2, "Appending X(9am) after locked Y(11am) must be refused")
    }

    // MARK: — Shake feedback on refused drop

    /// When a drop is refused because it would violate a locked event's time order,
    /// the VM sets shakingEventIDs to the IDs of the locked events that blocked it.
    func testRefusedReorderPopulatesShakingIDs() throws {
        let context = ctx
        let vm = TimelineViewModel()

        // [A(9am), B(10am, locked), C(11am)]
        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        setTime(events[0], hour: 9, context: context)
        setTime(events[1], hour: 10, context: context); events[1].isTimeLocked = true
        setTime(events[2], hour: 11, context: context)
        try context.save()

        // Drag C(11am) before B(10am, locked) → [A, C(11am), B(10am, locked)] → violation
        let moved = vm.reorderEvent(draggedID: events[2].id!.uuidString,
                                    before: events[1], in: day, context: context)

        XCTAssertFalse(moved)
        XCTAssertTrue(vm.shakingEventIDs.contains(events[1].id!),
                      "shakingEventIDs must contain the violated locked event B")
    }

    /// When an append is refused due to a lock violation, shakingEventIDs contains
    /// the blocking locked event's ID.
    func testRefusedAppendPopulatesShakingIDs() throws {
        let context = ctx
        let vm = TimelineViewModel()

        // [X(9am), Y(11am, locked)] — appending X to end puts it after Y → violation
        let (day, events) = makeDay(eventTitles: ["X", "Y"], context: context)
        setTime(events[0], hour: 9, context: context)
        setTime(events[1], hour: 11, context: context); events[1].isTimeLocked = true
        try context.save()

        let moved = vm.appendEvent(draggedID: events[0].id!.uuidString, to: day, context: context)

        XCTAssertFalse(moved)
        XCTAssertTrue(vm.shakingEventIDs.contains(events[1].id!),
                      "shakingEventIDs must contain the violated locked event Y")
    }

    // MARK: — Cross-day reorder

    /// Dragging an event from Day 1 and dropping it before an event in Day 2
    /// moves it to Day 2 and inserts it at the correct position.
    func testReorderMovesEventCrossDay() throws {
        let context = ctx
        let vm = TimelineViewModel()

        let (day1, events1) = makeDay(eventTitles: ["A", "B"], context: context)
        let (day2, events2) = makeDay(eventTitles: ["X", "Y"], context: context)

        // Move "A" from Day 1 to before "Y" in Day 2 → Day 2 should be [X, A, Y]
        vm.reorderEvent(draggedID: events1[0].id!.uuidString,
                        before: events2[1],
                        in: day2,
                        context: context)

        let day2Order = day2.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(day2Order.map(\.title), ["X", "A", "Y"])
    }

    /// After a cross-day reorder the source day's remaining events keep their
    /// original sortOrders (fractional indexing: only the moved event is written,
    /// relative order of the remaining events is preserved without renumbering).
    func testReorderPreservesSourceDaySortOrdersAfterCrossMove() throws {
        let context = ctx
        let vm = TimelineViewModel()

        let (day1, events1) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        let (day2, events2) = makeDay(eventTitles: ["X"], context: context)

        // Move "B" (sortOrder 1) from Day 1 to Day 2
        vm.reorderEvent(draggedID: events1[1].id!.uuidString,
                        before: events2[0],
                        in: day2,
                        context: context)

        let day1Order = day1.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        // "A"(0) and "C"(2) remain — source day is NOT renumbered (one CloudKit write)
        XCTAssertEqual(day1Order.map(\.title), ["A", "C"])
        XCTAssertEqual(day1Order.map(\.sortOrder), [0, 2])
    }

    /// Dragged event's .day relationship is updated to the target day.
    func testReorderUpdatesEventDayRelationship() throws {
        let context = ctx
        let vm = TimelineViewModel()

        let (_, events1) = makeDay(eventTitles: ["A"], context: context)
        let (day2, events2) = makeDay(eventTitles: ["X"], context: context)

        vm.reorderEvent(draggedID: events1[0].id!.uuidString,
                        before: events2[0],
                        in: day2,
                        context: context)

        XCTAssertEqual(events1[0].day?.id, day2.id)
    }

    // MARK: — Cross-day append

    /// Appending an event from Day 1 to Day 2 moves it to the end of Day 2.
    func testAppendMovesEventCrossDay() throws {
        let context = ctx
        let vm = TimelineViewModel()

        let (_, events1) = makeDay(eventTitles: ["A", "B"], context: context)
        let (day2, _)    = makeDay(eventTitles: ["X", "Y"], context: context)

        vm.appendEvent(draggedID: events1[0].id!.uuidString, to: day2, context: context)

        let day2Order = day2.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(day2Order.map(\.title), ["X", "Y", "A"])
    }

    /// After a cross-day append the source day's remaining events keep their
    /// original sortOrders (fractional indexing: only the appended event is written,
    /// relative order of the remaining events is preserved without renumbering).
    func testAppendPreservesSourceDaySortOrdersAfterCrossMove() throws {
        let context = ctx
        let vm = TimelineViewModel()

        let (day1, events1) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        let (day2, _)       = makeDay(eventTitles: ["X"], context: context)

        vm.appendEvent(draggedID: events1[0].id!.uuidString, to: day2, context: context)

        let day1Order = day1.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        // "B"(1) and "C"(2) remain — source day is NOT renumbered (one CloudKit write)
        XCTAssertEqual(day1Order.map(\.title), ["B", "C"])
        XCTAssertEqual(day1Order.map(\.sortOrder), [1, 2])
    }

    /// Appending a time-locked event is a no-op.
    func testAppendIgnoresTimeLocked() throws {
        let context = ctx
        let vm = TimelineViewModel()

        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        events[0].isTimeLocked = true
        try context.save()

        vm.appendEvent(draggedID: events[0].id!.uuidString, to: day, context: context)

        let reordered = day.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(reordered.map(\.title), ["A", "B", "C"])
    }
}
