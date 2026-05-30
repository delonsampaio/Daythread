//
//  ConflictDetectionTests.swift
//  DaythreadTests
//
//  Unit tests for ScheduleEngine.findConflicts — pure interval math.
//  Tests must fail before ScheduleEngine exists; all must pass once implemented.
//

import XCTest
import CoreData
@testable import Daythread

@MainActor
final class ConflictDetectionTests: XCTestCase {

    // MARK: — Helpers

    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).viewContext
    }

    /// Builds a Date for today at `hour`:`minute`.
    private func t(_ hour: Int, _ minute: Int = 0) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    private func makeEvent(
        title: String = "Event",
        startHour: Int? = nil, startMinute: Int = 0,
        endHour:   Int? = nil, endMinute:   Int = 0,
        category: EventCategory = .activity,
        isTimeLocked: Bool = false,
        context: NSManagedObjectContext
    ) -> TripEvent {
        let event = TripEvent(context: context)
        event.id = UUID()
        event.title = title
        event.category = category
        event.isTimeLocked = isTimeLocked
        event.sortOrder = 0
        event.notes = ""
        if let sh = startHour { event.startTime = t(sh, startMinute) }
        if let eh = endHour   { event.endTime   = t(eh, endMinute) }
        return event
    }

    // MARK: — Group 1: Overlap geometry

    func testConflictPartialOverlapBStartsDuringA() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: 9, endHour: 11, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [b])
        XCTAssertEqual(result.map(\.title), ["B"])
    }

    func testConflictPartialOverlapAStartsDuringB() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: 8, endHour: 10, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(9), endTime: t(11), among: [b])
        XCTAssertEqual(result.map(\.title), ["B"])
    }

    func testConflictAFullyContainsB() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: 9, endHour: 10, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(12), among: [b])
        XCTAssertEqual(result.map(\.title), ["B"])
    }

    func testConflictBFullyContainsA() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: 8, endHour: 12, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(9), endTime: t(10), among: [b])
        XCTAssertEqual(result.map(\.title), ["B"])
    }

    func testConflictIdenticalWindows() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: 8, endHour: 10, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [b])
        XCTAssertEqual(result.map(\.title), ["B"])
    }

    func testNoConflictAdjacentBStartsAtAEnd() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: 10, endHour: 12, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [b])
        XCTAssertTrue(result.isEmpty, "Back-to-back events must not conflict")
    }

    func testNoConflictAdjacentAStartsAtBEnd() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: 8, endHour: 10, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(10), endTime: t(12), among: [b])
        XCTAssertTrue(result.isEmpty, "Back-to-back events must not conflict")
    }

    func testNoConflictGapBetweenABeforeB() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: 10, endHour: 11, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(9), among: [b])
        XCTAssertTrue(result.isEmpty)
    }

    func testNoConflictGapBetweenBBeforeA() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: 8, endHour: 9, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(10), endTime: t(11), among: [b])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: — Group 2: Missing time fields

    func testNoConflictWhenCandidateHasNilStartTime() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: nil, endHour: 11, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [b])
        XCTAssertTrue(result.isEmpty, "Candidate missing startTime must be skipped")
    }

    func testNoConflictWhenCandidateHasNilEndTime() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: 9, endHour: nil, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [b])
        XCTAssertTrue(result.isEmpty, "Candidate missing endTime must be skipped")
    }

    func testNoConflictWhenCandidateIsFullyUntimed() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [b])
        XCTAssertTrue(result.isEmpty, "Untimed candidate must be skipped")
    }

    func testNoConflictWhenAllCandidatesAreUntimed() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", context: ctx)
        let c = makeEvent(title: "C", context: ctx)
        let d = makeEvent(title: "D", context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [b, c, d])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: — Group 3: Self-exclusion

    func testExcludesEditingEventFromConflictResults() throws {
        let ctx = makeContext()
        let a = makeEvent(title: "A", startHour: 8, endHour: 10, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [a], excludingID: a.id)
        XCTAssertTrue(result.isEmpty, "Editing event must not be self-reported")
    }

    func testEditingEventNotSelfReportedWhenOtherConflictExists() throws {
        let ctx = makeContext()
        let a = makeEvent(title: "A", startHour: 8, endHour: 10, context: ctx)
        let b = makeEvent(title: "B", startHour: 9, endHour: 11, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [a, b], excludingID: a.id)
        XCTAssertEqual(result.map(\.title), ["B"])
    }

    func testNilExcludingIDExcludesNoCandidates() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: 9, endHour: 11, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [b], excludingID: nil)
        XCTAssertEqual(result.map(\.title), ["B"])
    }

    // MARK: — Group 4: Multiple conflicts

    func testReturnsAllConflictingEventsNotJustFirst() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: 9, endHour: 10, context: ctx)
        let c = makeEvent(title: "C", startHour: 10, startMinute: 30, endHour: 11, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(12), among: [b, c])
        XCTAssertEqual(Set(result.map(\.title)), ["B", "C"])
    }

    func testReturnsThreeConflicts() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: 9,  endHour: 10, context: ctx)
        let c = makeEvent(title: "C", startHour: 10, startMinute: 30, endHour: 11, context: ctx)
        let d = makeEvent(title: "D", startHour: 11, startMinute: 30, endHour: 12, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(12), among: [b, c, d])
        XCTAssertEqual(Set(result.map(\.title)), ["B", "C", "D"])
    }

    func testMixedCandidatesOnlyOverlappingOnesReturned() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: 10, endHour: 12, context: ctx)
        let c = makeEvent(title: "C", startHour: 12, endHour: 14, context: ctx)
        let d = makeEvent(title: "D", startHour: 6,  endHour: 8,  context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(9), endTime: t(11), among: [b, c, d])
        XCTAssertEqual(result.map(\.title), ["B"])
    }

    // MARK: — Group 5: Empty / no-overlap

    func testNoConflictWhenCandidatesListIsEmpty() {
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testNoConflictWhenNoCandidatesOverlap() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: 11, endHour: 12, context: ctx)
        let c = makeEvent(title: "C", startHour: 13, endHour: 14, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(9), among: [b, c])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: — Group 6: Locked events

    func testConflictDetectedAgainstLockedEvent() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: 9, endHour: 11, isTimeLocked: true, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [b])
        XCTAssertEqual(result.map(\.title), ["B"], "Locked events are still conflict candidates")
    }

    func testLockStatusDoesNotChangeConflictResult() throws {
        let ctx = makeContext()
        let unlocked = makeEvent(title: "Unlocked", startHour: 9, endHour: 11, isTimeLocked: false, context: ctx)
        let locked   = makeEvent(title: "Locked",   startHour: 9, endHour: 11, isTimeLocked: true,  context: ctx)
        let rU = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [unlocked])
        let rL = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [locked])
        XCTAssertFalse(rU.isEmpty)
        XCTAssertFalse(rL.isEmpty, "isTimeLocked must not change conflict detection")
    }

    // MARK: — Group 7: Category irrelevance

    func testConflictDetectedForTransitCategoryEvent() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "Train", startHour: 9, endHour: 11, category: .train, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [b])
        XCTAssertEqual(result.map(\.title), ["Train"])
    }

    // MARK: — Group 8: Degenerate windows

    func testNoConflictWhenEndTimeBeforeStartTime() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: 9, endHour: 11, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(10), endTime: t(8), among: [b])
        XCTAssertTrue(result.isEmpty, "Inverted window must return no conflicts")
    }

    func testNoConflictWhenEndTimeEqualsStartTime() throws {
        let ctx = makeContext()
        let b = makeEvent(title: "B", startHour: 8, endHour: 10, context: ctx)
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(8), among: [b])
        XCTAssertTrue(result.isEmpty, "Zero-duration window must return no conflicts")
    }
}
