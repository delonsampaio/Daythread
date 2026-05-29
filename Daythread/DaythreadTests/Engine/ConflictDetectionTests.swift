//
//  ConflictDetectionTests.swift
//  DaythreadTests
//
//  Created by Delon Sampaio on 5/29/26.
//
//  Unit tests for ScheduleEngine.findConflicts — pure interval math,
//  no ViewModel or SwiftUI involved.
//
//  ALL tests must fail before ScheduleEngine exists. Once the engine is
//  written the full suite must go green with zero modifications to these tests.
//

import XCTest
import SwiftData
@testable import Daythread

private let conflictSchema = Schema([
    Trip.self, TripDay.self, TripEvent.self, TransitDetails.self,
    LodgingInfo.self, TripMember.self, TripDocument.self,
    TripExpense.self, PreTripTask.self
])

@MainActor
final class ConflictDetectionTests: XCTestCase {

    // MARK: — Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(
            schema: conflictSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: conflictSchema, configurations: config)
    }

    /// Builds a Date for today at `hour`:`minute`.
    private func t(_ hour: Int, _ minute: Int = 0) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    /// Creates a TripEvent with optional start/end times.
    /// Passing nil for startHour or endHour leaves that field as nil on the model.
    private func makeEvent(
        title: String = "Event",
        startHour: Int? = nil, startMinute: Int = 0,
        endHour:   Int? = nil, endMinute:   Int = 0,
        category: EventCategory = .activity,
        isTimeLocked: Bool = false,
        context: ModelContext
    ) -> TripEvent {
        let event = TripEvent(title: title, category: category, sortOrder: 0)
        context.insert(event)
        event.isTimeLocked = isTimeLocked
        if let sh = startHour { event.startTime = t(sh, startMinute) }
        if let eh = endHour   { event.endTime   = t(eh, endMinute) }
        return event
    }

    // MARK: — Group 1: Overlap geometry

    /// B starts during A → conflict.
    /// A(8–10am), B(9–11am): B's start falls inside A's window.
    func testConflictPartialOverlapBStartsDuringA() throws {
        let ctx = ModelContext(try makeContainer())
        let b = makeEvent(title: "B", startHour: 9, endHour: 11, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [b])

        XCTAssertEqual(result.map(\.title), ["B"])
    }

    /// A starts during B → conflict.
    /// A(9–11am), B(8–10am): A's start falls inside B's window.
    func testConflictPartialOverlapAStartsDuringB() throws {
        let ctx = ModelContext(try makeContainer())
        let b = makeEvent(title: "B", startHour: 8, endHour: 10, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(9), endTime: t(11), among: [b])

        XCTAssertEqual(result.map(\.title), ["B"])
    }

    /// A fully contains B → conflict.
    /// A(8am–12pm), B(9–10am): B's entire window sits inside A.
    func testConflictAFullyContainsB() throws {
        let ctx = ModelContext(try makeContainer())
        let b = makeEvent(title: "B", startHour: 9, endHour: 10, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(12), among: [b])

        XCTAssertEqual(result.map(\.title), ["B"])
    }

    /// B fully contains A → conflict.
    /// A(9–10am), B(8am–12pm): A's entire window sits inside B.
    func testConflictBFullyContainsA() throws {
        let ctx = ModelContext(try makeContainer())
        let b = makeEvent(title: "B", startHour: 8, endHour: 12, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(9), endTime: t(10), among: [b])

        XCTAssertEqual(result.map(\.title), ["B"])
    }

    /// A and B share the exact same window → conflict.
    func testConflictIdenticalWindows() throws {
        let ctx = ModelContext(try makeContainer())
        let b = makeEvent(title: "B", startHour: 8, endHour: 10, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [b])

        XCTAssertEqual(result.map(\.title), ["B"])
    }

    /// A(8–10am) adjacent to B(10am–12pm): B starts exactly at A's end → NOT a conflict.
    func testNoConflictAdjacentBStartsAtAEnd() throws {
        let ctx = ModelContext(try makeContainer())
        let b = makeEvent(title: "B", startHour: 10, endHour: 12, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [b])

        XCTAssertTrue(result.isEmpty,
                      "Back-to-back events touching at a single boundary must not conflict")
    }

    /// A(10am–12pm) adjacent to B(8–10am): A starts exactly at B's end → NOT a conflict.
    func testNoConflictAdjacentAStartsAtBEnd() throws {
        let ctx = ModelContext(try makeContainer())
        let b = makeEvent(title: "B", startHour: 8, endHour: 10, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(10), endTime: t(12), among: [b])

        XCTAssertTrue(result.isEmpty,
                      "Back-to-back events touching at a single boundary must not conflict")
    }

    /// Gap between A and B, A before B → no conflict.
    func testNoConflictGapBetweenABeforeB() throws {
        let ctx = ModelContext(try makeContainer())
        let b = makeEvent(title: "B", startHour: 10, endHour: 11, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(9), among: [b])

        XCTAssertTrue(result.isEmpty)
    }

    /// Gap between A and B, B entirely before A → no conflict.
    func testNoConflictGapBetweenBBeforeA() throws {
        let ctx = ModelContext(try makeContainer())
        let b = makeEvent(title: "B", startHour: 8, endHour: 9, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(10), endTime: t(11), among: [b])

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: — Group 2: Missing time fields on candidates

    /// Candidate B has no startTime → skipped, no conflict reported.
    func testNoConflictWhenCandidateHasNilStartTime() throws {
        let ctx = ModelContext(try makeContainer())
        // endHour set but startHour nil — incomplete window, must be ignored
        let b = makeEvent(title: "B", startHour: nil, endHour: 11, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [b])

        XCTAssertTrue(result.isEmpty, "Candidate missing startTime must be skipped")
    }

    /// Candidate B has no endTime → skipped, no conflict reported.
    func testNoConflictWhenCandidateHasNilEndTime() throws {
        let ctx = ModelContext(try makeContainer())
        // startHour set but endHour nil — incomplete window, must be ignored
        let b = makeEvent(title: "B", startHour: 9, endHour: nil, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [b])

        XCTAssertTrue(result.isEmpty, "Candidate missing endTime must be skipped")
    }

    /// Candidate B has neither startTime nor endTime → skipped.
    func testNoConflictWhenCandidateIsFullyUntimed() throws {
        let ctx = ModelContext(try makeContainer())
        let b = makeEvent(title: "B", context: ctx) // no times

        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [b])

        XCTAssertTrue(result.isEmpty, "Untimed candidate must be skipped")
    }

    /// All candidates are untimed → engine returns empty result.
    func testNoConflictWhenAllCandidatesAreUntimed() throws {
        let ctx = ModelContext(try makeContainer())
        let b = makeEvent(title: "B", context: ctx)
        let c = makeEvent(title: "C", context: ctx)
        let d = makeEvent(title: "D", context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10),
                                                  among: [b, c, d])

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: — Group 3: Self-exclusion

    /// The event being edited is the only candidate and is excluded via excludingID → no conflict.
    func testExcludesEditingEventFromConflictResults() throws {
        let ctx = ModelContext(try makeContainer())
        let a = makeEvent(title: "A", startHour: 8, endHour: 10, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10),
                                                  among: [a], excludingID: a.id)

        XCTAssertTrue(result.isEmpty, "The editing event must not be reported as its own conflict")
    }

    /// Editing A; candidates contain both A and B(9–11am).
    /// Only B is returned — A is excluded, it is not self-reported.
    func testEditingEventNotSelfReportedWhenOtherConflictExists() throws {
        let ctx = ModelContext(try makeContainer())
        let a = makeEvent(title: "A", startHour: 8, endHour: 10, context: ctx)
        let b = makeEvent(title: "B", startHour: 9, endHour: 11, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10),
                                                  among: [a, b], excludingID: a.id)

        XCTAssertEqual(result.map(\.title), ["B"])
    }

    /// Passing excludingID: nil excludes nothing — all overlapping candidates are returned.
    func testNilExcludingIDExcludesNoCandidates() throws {
        let ctx = ModelContext(try makeContainer())
        let b = makeEvent(title: "B", startHour: 9, endHour: 11, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10),
                                                  among: [b], excludingID: nil)

        XCTAssertEqual(result.map(\.title), ["B"])
    }

    // MARK: — Group 4: Multiple conflicts

    /// New event(8am–12pm) overlaps both B(9–10am) and C(10:30–11am) → both returned.
    func testReturnsAllConflictingEventsNotJustFirst() throws {
        let ctx = ModelContext(try makeContainer())
        let b = makeEvent(title: "B", startHour: 9,  endHour: 10, context: ctx)
        let c = makeEvent(title: "C", startHour: 10, startMinute: 30, endHour: 11, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(12),
                                                  among: [b, c])

        XCTAssertEqual(Set(result.map(\.title)), ["B", "C"])
    }

    /// New event(8am–12pm) overlaps B, C, and D → all three returned.
    func testReturnsThreeConflicts() throws {
        let ctx = ModelContext(try makeContainer())
        let b = makeEvent(title: "B", startHour: 9,  endHour: 10, context: ctx)
        let c = makeEvent(title: "C", startHour: 10, startMinute: 30, endHour: 11, context: ctx)
        let d = makeEvent(title: "D", startHour: 11, startMinute: 30, endHour: 12, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(12),
                                                  among: [b, c, d])

        XCTAssertEqual(Set(result.map(\.title)), ["B", "C", "D"])
    }

    /// Mixed candidates: some overlap, some don't — only the overlapping ones are returned.
    func testMixedCandidatesOnlyOverlappingOnesReturned() throws {
        let ctx = ModelContext(try makeContainer())
        // Overlaps A(9–11am)
        let b = makeEvent(title: "B", startHour: 10, endHour: 12, context: ctx)
        // Does NOT overlap A(9–11am)
        let c = makeEvent(title: "C", startHour: 12, endHour: 14, context: ctx)
        let d = makeEvent(title: "D", startHour: 6,  endHour: 8,  context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(9), endTime: t(11),
                                                  among: [b, c, d])

        XCTAssertEqual(result.map(\.title), ["B"],
                       "Only B overlaps — C and D must not be returned")
    }

    // MARK: — Group 5: Empty / no-overlap candidates

    /// Empty candidates list → no conflicts possible.
    func testNoConflictWhenCandidatesListIsEmpty() {
        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [])
        XCTAssertTrue(result.isEmpty)
    }

    /// Candidates exist but none overlap the checking window → empty result.
    func testNoConflictWhenNoCandidatesOverlap() throws {
        let ctx = ModelContext(try makeContainer())
        let b = makeEvent(title: "B", startHour: 11, endHour: 12, context: ctx)
        let c = makeEvent(title: "C", startHour: 13, endHour: 14, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(9),
                                                  among: [b, c])

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: — Group 6: Locked events

    /// A locked candidate still counts as a conflict — lock status is irrelevant.
    func testConflictDetectedAgainstLockedEvent() throws {
        let ctx = ModelContext(try makeContainer())
        let b = makeEvent(title: "B", startHour: 9, endHour: 11,
                          isTimeLocked: true, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [b])

        XCTAssertEqual(result.map(\.title), ["B"],
                       "Locked events are still conflict candidates")
    }

    /// Unlocked and locked versions of the same window both conflict — lock makes no difference.
    func testLockStatusDoesNotChangeConflictResult() throws {
        let ctx = ModelContext(try makeContainer())
        let unlocked = makeEvent(title: "Unlocked", startHour: 9, endHour: 11,
                                 isTimeLocked: false, context: ctx)
        let locked   = makeEvent(title: "Locked",   startHour: 9, endHour: 11,
                                 isTimeLocked: true,  context: ctx)

        let resultUnlocked = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10),
                                                          among: [unlocked])
        let resultLocked   = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10),
                                                          among: [locked])

        XCTAssertFalse(resultUnlocked.isEmpty)
        XCTAssertFalse(resultLocked.isEmpty,
                       "isTimeLocked must not change conflict detection behaviour")
    }

    // MARK: — Group 7: Category irrelevance

    /// Transit-category candidate overlapping → returned as a conflict.
    func testConflictDetectedForTransitCategoryEvent() throws {
        let ctx = ModelContext(try makeContainer())
        let b = makeEvent(title: "Train", startHour: 9, endHour: 11,
                          category: .train, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(10), among: [b])

        XCTAssertEqual(result.map(\.title), ["Train"],
                       "Event category must not affect conflict detection")
    }

    // MARK: — Group 8: Degenerate checking windows

    /// endTime is before startTime (inverted window) → return [] immediately.
    func testNoConflictWhenEndTimeBeforeStartTime() throws {
        let ctx = ModelContext(try makeContainer())
        // B would normally conflict, but the checking window is inverted
        let b = makeEvent(title: "B", startHour: 9, endHour: 11, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(10), endTime: t(8), among: [b])

        XCTAssertTrue(result.isEmpty, "Inverted window must return no conflicts")
    }

    /// endTime equals startTime (zero-duration window) → return [] immediately.
    func testNoConflictWhenEndTimeEqualsStartTime() throws {
        let ctx = ModelContext(try makeContainer())
        let b = makeEvent(title: "B", startHour: 8, endHour: 10, context: ctx)

        let result = ScheduleEngine.findConflicts(startTime: t(8), endTime: t(8), among: [b])

        XCTAssertTrue(result.isEmpty, "Zero-duration window must return no conflicts")
    }
}
