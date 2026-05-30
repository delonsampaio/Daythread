//
//  ChronologicalOrderTests.swift
//  DaythreadTests
//
//  Created by Delon Sampaio on 5/29/26.
//
//  Tests for:
//  • TimelineViewModel.outOfOrderEventIDs(in:)  — detects unlocked timed events
//    whose visual sortOrder contradicts their startTime chronology.
//  • TimelineViewModel.sortDayByTime(_:context:) — reorders a day's events so
//    untimed events float to the top and timed events sort chronologically.
//

import XCTest
import CoreData
@testable import Daythread

@MainActor
final class ChronologicalOrderTests: XCTestCase {

    // MARK: — Helpers

    private var ctx: NSManagedObjectContext {
        PersistenceController(inMemory: true).viewContext
    }

    private func makeDay(eventTitles: [String], context: NSManagedObjectContext) -> (TripDay, [TripEvent]) {
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
            e.sortOrder = i * 1024
            e.day = day
            return e
        }
        try? context.save()
        return (day, events)
    }

    /// Sets only startTime — outOfOrderEventIDs and sortDayByTime both key on startTime.
    private func setTime(_ event: TripEvent, hour: Int, minute: Int = 0) {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour; c.minute = minute
        event.startTime = Calendar.current.date(from: c)!
    }

    // MARK: — outOfOrderEventIDs

    /// Walk(8:37) placed above Breakfast(7:35) → both flagged.
    /// Walk is out of order because something after it has an earlier time.
    /// Breakfast is out of order because something before it has a later time.
    func testOutOfOrderFlagsBothEventsWhenOrderInverted() throws {
        let context = ctx
        let (_, events) = makeDay(eventTitles: ["Walk", "Breakfast"], context: context)
        setTime(events[0], hour: 8, minute: 37)  // Walk at 8:37 AM — placed first
        setTime(events[1], hour: 7, minute: 35)  // Breakfast at 7:35 AM — placed second

        let result = TimelineViewModel().outOfOrderEventIDs(in: events)

        XCTAssertEqual(result, [events[0].id, events[1].id])
    }

    /// Breakfast(7:35) before Walk(8:37) — correct chronological order → empty set.
    func testOutOfOrderReturnsEmptyForChronologicalOrder() throws {
        let context = ctx
        let (_, events) = makeDay(eventTitles: ["Breakfast", "Walk"], context: context)
        setTime(events[0], hour: 7, minute: 35)
        setTime(events[1], hour: 8, minute: 37)

        let result = TimelineViewModel().outOfOrderEventIDs(in: events)

        XCTAssertTrue(result.isEmpty)
    }

    /// Untimed events are transparent — they never trigger or absorb violations.
    func testOutOfOrderIgnoresUntimedEvents() throws {
        let context = ctx
        let (_, events) = makeDay(eventTitles: ["Wait", "Walk", "Breakfast"], context: context)
        // events[0] = Wait — no time set
        setTime(events[1], hour: 8, minute: 37)  // Walk placed second
        setTime(events[2], hour: 7, minute: 35)  // Breakfast placed third

        let result = TimelineViewModel().outOfOrderEventIDs(in: events)

        XCTAssertFalse(result.contains(events[0].id), "Untimed event must not be flagged")
        XCTAssertTrue(result.contains(events[1].id),  "Walk(8:37) placed above Breakfast(7:35) must be flagged")
        XCTAssertTrue(result.contains(events[2].id),  "Breakfast(7:35) placed below Walk(8:37) must be flagged")
    }

    /// Locked events already have their own amber indicator — skip them here.
    func testOutOfOrderSkipsLockedEvents() throws {
        let context = ctx
        let (_, events) = makeDay(eventTitles: ["Walk", "Breakfast"], context: context)
        setTime(events[0], hour: 8, minute: 37)
        events[0].isTimeLocked = true              // Walk is locked
        setTime(events[1], hour: 7, minute: 35)   // Breakfast placed after

        let result = TimelineViewModel().outOfOrderEventIDs(in: events)

        XCTAssertFalse(result.contains(events[0].id),
                       "Locked event must be skipped — violatedLockIDs handles it")
        XCTAssertTrue(result.contains(events[1].id),
                      "Unlocked Breakfast(7:35) placed after locked Walk(8:37) must be flagged")
    }

    /// Empty event list → no violations.
    func testOutOfOrderReturnsEmptyForEmptyList() {
        let result = TimelineViewModel().outOfOrderEventIDs(in: [])
        XCTAssertTrue(result.isEmpty)
    }

    /// Single timed event — nothing to compare against → no violation.
    func testOutOfOrderReturnsEmptyForSingleTimedEvent() throws {
        let context = ctx
        let (_, events) = makeDay(eventTitles: ["Walk"], context: context)
        setTime(events[0], hour: 8)

        let result = TimelineViewModel().outOfOrderEventIDs(in: events)

        XCTAssertTrue(result.isEmpty)
    }

    /// Completely reversed order — all three timed events flagged.
    func testOutOfOrderFlagsAllEventsInCompletelyReversedOrder() throws {
        let context = ctx
        let (_, events) = makeDay(eventTitles: ["C", "B", "A"], context: context)
        setTime(events[0], hour: 9)   // C(9am) placed first
        setTime(events[1], hour: 8)   // B(8am) placed second
        setTime(events[2], hour: 7)   // A(7am) placed third

        let result = TimelineViewModel().outOfOrderEventIDs(in: events)

        XCTAssertEqual(result, [events[0].id, events[1].id, events[2].id])
    }

    // MARK: — sortDayByTime

    /// Out-of-order timed events get sorted chronologically.
    func testSortDayByTimeOrdersTimedEventsChronologically() throws {
        let context = ctx
        let vm = TimelineViewModel()
        let (day, events) = makeDay(eventTitles: ["Walk", "Breakfast"], context: context)
        setTime(events[0], hour: 8, minute: 37)  // Walk placed first but has later time
        setTime(events[1], hour: 7, minute: 35)  // Breakfast placed second but has earlier time
        try context.save()

        vm.sortDayByTime(day, context: context)

        let sorted = day.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(sorted.map(\.title), ["Breakfast", "Walk"])
    }

    /// Untimed events always come before timed events after sorting.
    func testSortDayByTimePutsUntimedEventsBeforeTimedEvents() throws {
        let context = ctx
        let vm = TimelineViewModel()
        let (day, events) = makeDay(eventTitles: ["Walk", "Wait"], context: context)
        setTime(events[0], hour: 8)   // Walk has a time
        // events[1] = Wait — no time
        try context.save()

        vm.sortDayByTime(day, context: context)

        let sorted = day.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(sorted.map(\.title), ["Wait", "Walk"])
    }

    /// Multiple untimed events preserve their relative order (by original sortOrder) at the top.
    func testSortDayByTimePreservesRelativeOrderOfUntimedEvents() throws {
        let context = ctx
        let vm = TimelineViewModel()
        // Untimed1 < Untimed2 by original sortOrder — that relative order must be kept.
        let (day, events) = makeDay(eventTitles: ["Untimed1", "Untimed2", "Walk"], context: context)
        setTime(events[2], hour: 8)
        try context.save()

        vm.sortDayByTime(day, context: context)

        let sorted = day.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(sorted.map(\.title), ["Untimed1", "Untimed2", "Walk"])
    }

    /// Mixed: timed events reorder, untimed float to top, locked timed events still sort.
    func testSortDayByTimeSortsMixedDayCorrectly() throws {
        let context = ctx
        let vm = TimelineViewModel()
        let (day, events) = makeDay(eventTitles: ["Walk", "Wait", "Breakfast"], context: context)
        setTime(events[0], hour: 8, minute: 37)   // Walk — timed, placed first
        // events[1] = Wait — untimed, placed second
        setTime(events[2], hour: 7, minute: 35)   // Breakfast — timed, placed third
        try context.save()

        vm.sortDayByTime(day, context: context)

        let sorted = day.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(sorted.map(\.title), ["Wait", "Breakfast", "Walk"])
    }

    /// After sorting, sortOrder values use 1024 spacing (fractional indexing compatibility).
    func testSortDayByTimeUses1024Spacing() throws {
        let context = ctx
        let vm = TimelineViewModel()
        let (day, events) = makeDay(eventTitles: ["B", "A"], context: context)
        setTime(events[0], hour: 10)
        setTime(events[1], hour: 9)
        try context.save()

        vm.sortDayByTime(day, context: context)

        let sorted = day.eventsArray.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(sorted.map(\.sortOrder), [0, 1024])
    }
}
