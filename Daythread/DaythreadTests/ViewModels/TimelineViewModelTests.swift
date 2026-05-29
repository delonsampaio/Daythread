//
//  TimelineViewModelTests.swift
//  DaythreadTests
//
//  Created by Delon Sampaio on 5/27/26.
//
//  Tests for TimelineViewModel drag-and-drop reordering logic.
//  Uses an in-memory container (cloudKitDatabase: .none) so saves are
//  synchronous and tests complete in well under 1 second.
//

import XCTest
import SwiftData
@testable import Daythread

private let schema = Schema([
    Trip.self, TripDay.self, TripEvent.self, TransitDetails.self,
    LodgingInfo.self, TripMember.self, TripDocument.self,
    TripExpense.self, PreTripTask.self
])

@MainActor
final class TimelineViewModelTests: XCTestCase {

    // MARK: — Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: config)
    }

    /// Sets up a trip with one day and the given event titles (sortOrder assigned 0, 1, 2…).
    private func makeDay(
        eventTitles: [String],
        context: ModelContext
    ) -> (TripDay, [TripEvent]) {
        let trip = Trip(name: "Test", destination: "Anywhere", startDate: .now, endDate: .now)
        context.insert(trip)

        let day = TripDay(date: .now, sortOrder: 0)
        context.insert(day)
        day.trip = trip

        let events: [TripEvent] = eventTitles.enumerated().map { i, title in
            let e = TripEvent(title: title, category: .activity, sortOrder: i)
            context.insert(e)
            e.day = day
            return e
        }
        try? context.save()
        return (day, events)
    }

    // MARK: — reorderEvent

    /// Dragging the last event to before the first event makes it first.
    func testReorderMakesLastEventFirst() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        // events[2] = "C" (sortOrder 2), drop before events[0] = "A"

        vm.reorderEvent(draggedID: events[2].id.uuidString,
                        before: events[0],
                        in: day,
                        context: context)

        let reordered = (day.events ?? []).sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(reordered.map(\.title), ["C", "A", "B"])
    }

    /// Dragging the first event to before the last event gives [B, A, C].
    func testReorderMovesFirstToSecondToLast() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        // events[0] = "A", drop before events[2] = "C" → [B, A, C]

        vm.reorderEvent(draggedID: events[0].id.uuidString,
                        before: events[2],
                        in: day,
                        context: context)

        let reordered = (day.events ?? []).sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(reordered.map(\.title), ["B", "A", "C"])
    }

    /// When the integer gap is exhausted (succ == 0, can't place before it),
    /// reorderEvent falls back to a full renumber using 1024 spacing.
    /// Dragging C(sortOrder 2) before A(sortOrder 0): midOrder(pred:nil, succ:0)
    /// returns nil → renumber → [0, 1024, 2048].
    func testReorderRenumbersWithFractionalSpacingWhenGapExhausted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)

        vm.reorderEvent(draggedID: events[2].id.uuidString,
                        before: events[0],
                        in: day,
                        context: context)

        let reordered = (day.events ?? []).sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(reordered.map(\.sortOrder), [0, 1024, 2048])
    }

    /// A time-locked event cannot be dragged — reorderEvent is a no-op for it.
    func testReorderIgnoresTimeLocked() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        events[2].isTimeLocked = true
        try context.save()

        vm.reorderEvent(draggedID: events[2].id.uuidString,
                        before: events[0],
                        in: day,
                        context: context)

        // Order must remain unchanged
        let reordered = (day.events ?? []).sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(reordered.map(\.title), ["A", "B", "C"])
    }

    /// An invalid UUID string (e.g. empty) is silently ignored.
    func testReorderWithInvalidIDIsNoop() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        let (day, events) = makeDay(eventTitles: ["A", "B"], context: context)

        vm.reorderEvent(draggedID: "not-a-uuid",
                        before: events[0],
                        in: day,
                        context: context)

        let reordered = (day.events ?? []).sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(reordered.map(\.title), ["A", "B"])
    }

    // MARK: — appendEvent

    /// Dragging the first event to the end moves it last.
    func testAppendMovesFirstToEnd() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)

        vm.appendEvent(draggedID: events[0].id.uuidString, to: day, context: context)

        let reordered = (day.events ?? []).sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(reordered.map(\.title), ["B", "C", "A"])
    }

    // MARK: — Lock-order conflict

    /// Helper: assigns a same-day Date at the given hour (and optional minute) to event.startTime.
    private func setTime(_ event: TripEvent, hour: Int, minute: Int = 0, context: ModelContext) {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour; c.minute = minute
        event.startTime = Calendar.current.date(from: c)!
    }

    /// Dragging an event to a position that would put a LOCKED event out of
    /// chronological order must be refused (returns false, order unchanged).
    func testReorderRefusesDropViolatingLockedEvent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        // [A(9am), B(10am, locked), C(11am)]
        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        setTime(events[0], hour: 9, context: context)
        setTime(events[1], hour: 10, context: context); events[1].isTimeLocked = true
        setTime(events[2], hour: 11, context: context)
        try context.save()

        // Drag C(11am) before B(10am, locked) → [A, C(11am), B(10am, locked)]
        // B(locked,10am) would have C(11am) immediately before it → violation.
        let moved = vm.reorderEvent(draggedID: events[2].id.uuidString,
                                    before: events[1], in: day, context: context)

        XCTAssertFalse(moved, "Drop must be refused: would put a 11am event before a locked 10am event")
        let order = (day.events ?? []).sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(order.map(\.title), ["A", "B", "C"], "Order must be unchanged after refused drop")
    }

    /// A drop that respects all locked events is allowed normally.
    func testReorderAllowsDropThatRespectsLockedOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        // [A(9am, locked), B(10am), C(11am)]
        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        setTime(events[0], hour: 9, context: context); events[0].isTimeLocked = true
        setTime(events[1], hour: 10, context: context)
        setTime(events[2], hour: 11, context: context)
        try context.save()

        // Drag C(11am) before B(10am) → [A(9am, locked), C(11am), B(10am)]
        // A stays first, and next event C(11am) > A(9am) → no violation.
        let moved = vm.reorderEvent(draggedID: events[2].id.uuidString,
                                    before: events[1], in: day, context: context)

        XCTAssertTrue(moved, "Drop should be allowed: locked event A is still in correct time order")
        let order = (day.events ?? []).sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(order.map(\.title), ["A", "C", "B"])
    }

    /// Events without a startTime are skipped in the lock check — only timed
    /// neighbors can trigger a violation.
    func testReorderIgnoresUntimedNeighborsInLockCheck() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        // [A(no time), B(10am, locked), C(no time)]
        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        setTime(events[1], hour: 10, context: context); events[1].isTimeLocked = true
        try context.save()

        // Drag C before A → [C, A, B(10am, locked)]
        // B has no timed neighbors → no violation, move allowed.
        let moved = vm.reorderEvent(draggedID: events[2].id.uuidString,
                                    before: events[0], in: day, context: context)

        XCTAssertTrue(moved)
        let order = (day.events ?? []).sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(order.map(\.title), ["C", "A", "B"])
    }

    /// Regression: dragging B(8:30pm) before an untimed C when locked A(8pm) sits
    /// between C and B must be refused. The untimed C masked the violation because
    /// the old check only looked at the immediate neighbor, not the nearest timed one.
    func testReorderRefusesWhenViolationIsHiddenByUntimedGap() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        // Order: [C(no time), A(8pm, locked), B(8:30pm)]
        let (day, events) = makeDay(eventTitles: ["C", "A", "B"], context: context)
        // events[0] = C — no startTime set
        setTime(events[1], hour: 20, minute: 0,  context: context); events[1].isTimeLocked = true
        setTime(events[2], hour: 20, minute: 30, context: context)
        try context.save()

        // Drag B(8:30pm) before C → proposed [B(8:30pm), C(no time), A(8pm, locked)]
        // Nearest timed predecessor of A = B(8:30pm) > A(8pm) → should be REFUSED
        let moved = vm.reorderEvent(draggedID: events[2].id.uuidString,
                                    before: events[0], in: day, context: context)

        XCTAssertFalse(moved, "Drop must be refused: B(8:30pm) is the nearest timed predecessor of locked A(8pm)")
        let order = (day.events ?? []).sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(order.map(\.title), ["C", "A", "B"], "Order must be unchanged")
    }

    /// appendEvent is also refused when it would violate a locked event's time order.
    func testAppendRefusesWhenViolatesLockedEvent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        // [A(9am, locked), B(10am), C(8am)]
        // Dragging C(8am) to end → [A(9am, locked), B(10am), C(8am)]
        // A(locked,9am): next is B(10am) > 9am ✓. No new violation from A.
        // Actually this test is about B being appended...
        // Let's test: [A(9am, locked), B(11am)] drag B to end → no change since B is already last.
        // Better test: [A(9am, locked), B(8am)] → append B → B moves to end → [A(9am,locked), B(8am)]
        // A(locked,9am): next = B(8am) < 9am → VIOLATION after append.
        let (day, events) = makeDay(eventTitles: ["A", "B"], context: context)
        setTime(events[0], hour: 9, context: context); events[0].isTimeLocked = true
        setTime(events[1], hour: 11, context: context)
        try context.save()

        // Add a third event at 8am so that appending it after locked 9am is a violation
        let early = TripEvent(title: "Early", category: .activity, sortOrder: 2)
        context.insert(early); early.day = day
        setTime(early, hour: 8, context: context)
        try context.save()

        let moved = vm.appendEvent(draggedID: early.id.uuidString, to: day, context: context)

        // [A(9am,locked), B(11am), Early(8am)] → A's next is B(11am) ✓, B's next is Early(8am) —
        // but neither B nor Early is locked, so no violation. Hmm.
        // Let me rethink: need a locked event BEFORE the appended position.
        // Actually the issue is append puts it LAST, so locked events before it in sortOrder
        // just need their NEXT neighbor checked. If B(11am) is locked and Early(8am) would be
        // placed after B → B(11am, locked): next = Early(8am) < 11am → VIOLATION.
        XCTAssertTrue(moved) // this specific case has no locked violation

        // Reset and test an actual violation case for append
        context.delete(early)
        try context.save()

        // [A(9am), B(11am, locked)] append A(9am) to end → [B(11am, locked), A(9am)]
        // B(11am, locked) at position 0: prev=none. Next=A(9am) < 11am → VIOLATION.
        let (day2, events2) = makeDay(eventTitles: ["X", "Y"], context: context)
        setTime(events2[0], hour: 9, context: context)
        setTime(events2[1], hour: 11, context: context); events2[1].isTimeLocked = true
        try context.save()

        let moved2 = vm.appendEvent(draggedID: events2[0].id.uuidString, to: day2, context: context)
        XCTAssertFalse(moved2, "Appending X(9am) after locked Y(11am) should be refused")
    }

    // MARK: — Shake feedback on refused drop

    /// When a drop is refused because it would violate a locked event's time order,
    /// the VM sets shakingEventIDs to the IDs of the locked events that blocked it.
    func testRefusedReorderPopulatesShakingIDs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        // [A(9am), B(10am, locked), C(11am)]
        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        setTime(events[0], hour: 9, context: context)
        setTime(events[1], hour: 10, context: context); events[1].isTimeLocked = true
        setTime(events[2], hour: 11, context: context)
        try context.save()

        // Drag C(11am) before B(10am, locked) → [A, C(11am), B(10am, locked)] → violation
        let moved = vm.reorderEvent(draggedID: events[2].id.uuidString,
                                    before: events[1], in: day, context: context)

        XCTAssertFalse(moved)
        XCTAssertTrue(vm.shakingEventIDs.contains(events[1].id),
                      "shakingEventIDs must contain the violated locked event B")
    }

    /// When an append is refused due to a lock violation, shakingEventIDs contains
    /// the blocking locked event's ID.
    func testRefusedAppendPopulatesShakingIDs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        // [X(9am), Y(11am, locked)] — appending X to end puts it after Y → violation
        let (day, events) = makeDay(eventTitles: ["X", "Y"], context: context)
        setTime(events[0], hour: 9, context: context)
        setTime(events[1], hour: 11, context: context); events[1].isTimeLocked = true
        try context.save()

        let moved = vm.appendEvent(draggedID: events[0].id.uuidString, to: day, context: context)

        XCTAssertFalse(moved)
        XCTAssertTrue(vm.shakingEventIDs.contains(events[1].id),
                      "shakingEventIDs must contain the violated locked event Y")
    }

    // MARK: — Cross-day reorder

    /// Dragging an event from Day 1 and dropping it before an event in Day 2
    /// moves it to Day 2 and inserts it at the correct position.
    func testReorderMovesEventCrossDay() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        let (day1, events1) = makeDay(eventTitles: ["A", "B"], context: context)
        let (day2, events2) = makeDay(eventTitles: ["X", "Y"], context: context)

        // Move "A" from Day 1 to before "Y" in Day 2 → Day 2 should be [X, A, Y]
        vm.reorderEvent(draggedID: events1[0].id.uuidString,
                        before: events2[1],
                        in: day2,
                        context: context)

        let day2Order = (day2.events ?? []).sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(day2Order.map(\.title), ["X", "A", "Y"])
    }

    /// After a cross-day reorder the source day's remaining events keep their
    /// original sortOrders (fractional indexing: only the moved event is written,
    /// relative order of the remaining events is preserved without renumbering).
    func testReorderPreservesSourceDaySortOrdersAfterCrossMove() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        let (day1, events1) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        let (day2, events2) = makeDay(eventTitles: ["X"], context: context)

        // Move "B" (sortOrder 1) from Day 1 to Day 2
        vm.reorderEvent(draggedID: events1[1].id.uuidString,
                        before: events2[0],
                        in: day2,
                        context: context)

        let day1Order = (day1.events ?? []).sorted { $0.sortOrder < $1.sortOrder }
        // "A"(0) and "C"(2) remain — source day is NOT renumbered (one CloudKit write)
        XCTAssertEqual(day1Order.map(\.title), ["A", "C"])
        XCTAssertEqual(day1Order.map(\.sortOrder), [0, 2])
    }

    /// Dragged event's .day relationship is updated to the target day.
    func testReorderUpdatesEventDayRelationship() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        let (day1, events1) = makeDay(eventTitles: ["A"], context: context)
        let (day2, events2) = makeDay(eventTitles: ["X"], context: context)

        vm.reorderEvent(draggedID: events1[0].id.uuidString,
                        before: events2[0],
                        in: day2,
                        context: context)

        XCTAssertEqual(events1[0].day?.id, day2.id)
    }

    // MARK: — Cross-day append

    /// Appending an event from Day 1 to Day 2 moves it to the end of Day 2.
    func testAppendMovesEventCrossDay() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        let (day1, events1) = makeDay(eventTitles: ["A", "B"], context: context)
        let (day2, _)       = makeDay(eventTitles: ["X", "Y"], context: context)

        vm.appendEvent(draggedID: events1[0].id.uuidString, to: day2, context: context)

        let day2Order = (day2.events ?? []).sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(day2Order.map(\.title), ["X", "Y", "A"])
    }

    /// After a cross-day append the source day's remaining events keep their
    /// original sortOrders (fractional indexing: only the appended event is written,
    /// relative order of the remaining events is preserved without renumbering).
    func testAppendPreservesSourceDaySortOrdersAfterCrossMove() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        let (day1, events1) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        let (day2, _)       = makeDay(eventTitles: ["X"], context: context)

        vm.appendEvent(draggedID: events1[0].id.uuidString, to: day2, context: context)

        let day1Order = (day1.events ?? []).sorted { $0.sortOrder < $1.sortOrder }
        // "B"(1) and "C"(2) remain — source day is NOT renumbered (one CloudKit write)
        XCTAssertEqual(day1Order.map(\.title), ["B", "C"])
        XCTAssertEqual(day1Order.map(\.sortOrder), [1, 2])
    }

    /// Appending a time-locked event is a no-op.
    func testAppendIgnoresTimeLocked() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = TimelineViewModel()

        let (day, events) = makeDay(eventTitles: ["A", "B", "C"], context: context)
        events[0].isTimeLocked = true
        try context.save()

        vm.appendEvent(draggedID: events[0].id.uuidString, to: day, context: context)

        let reordered = (day.events ?? []).sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(reordered.map(\.title), ["A", "B", "C"])
    }
}
