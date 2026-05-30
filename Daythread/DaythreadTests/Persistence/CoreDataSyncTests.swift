//
//  CoreDataSyncTests.swift
//  DaythreadTests
//
//  In-memory Core Data CRUD tests that verify the data layer is correct before
//  testing on a real device. Covers: zone-hopping rule, cascade deletes, enum
//  bridges, splitAmongJoined, and computed accessors.
//
//  Note: uniqueness constraints are intentionally absent — NSPersistentCloudKitContainer
//  rejects them at load time. Deduplication (if needed) must happen at the app layer.
//

import XCTest
import CoreData
@testable import Daythread

@MainActor
final class CoreDataSyncTests: XCTestCase {

    private var controller: PersistenceController!
    private var ctx: NSManagedObjectContext!

    override func setUpWithError() throws {
        controller = PersistenceController(inMemory: true)
        ctx = controller.viewContext
    }

    override func tearDownWithError() throws {
        controller = nil; ctx = nil
    }

    // MARK: — Zone-hopping prevention (link parent before first save)

    func test_event_linkedToParentBeforeSave_roundTrips() throws {
        let trip = Trip(context: ctx); trip.id = UUID(); trip.name = "Paris"
        let day  = TripDay(context: ctx); day.id = UUID(); day.trip = trip
        let event = TripEvent(context: ctx); event.id = UUID(); event.title = "Lunch"
        event.day = day
        try ctx.save()

        let fetched = try ctx.fetch(TripEvent.fetchRequest())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.day?.trip?.name, "Paris")
    }

    // MARK: — Cascade delete

    func test_deletingTrip_cascadesTo_daysAndEvents() throws {
        let trip = Trip(context: ctx); trip.id = UUID(); trip.name = "Tokyo"
        let day  = TripDay(context: ctx);  day.id  = UUID(); day.trip  = trip
        let ev   = TripEvent(context: ctx); ev.id  = UUID(); ev.day   = day; ev.title = "Ramen"
        try ctx.save()

        ctx.delete(trip)
        try ctx.save()

        XCTAssertEqual(try ctx.fetch(Trip.fetchRequest()).count, 0)
        XCTAssertEqual(try ctx.fetch(TripDay.fetchRequest()).count, 0)
        XCTAssertEqual(try ctx.fetch(TripEvent.fetchRequest()).count, 0)
    }

    func test_transitDetails_cascadeDeleteWithEvent() throws {
        let day   = TripDay(context: ctx);    day.id  = UUID()
        let event = TripEvent(context: ctx);  event.id = UUID(); event.day = day
        let td    = TransitDetails(context: ctx); td.id = UUID(); td.event = event
        try ctx.save()

        ctx.delete(event)
        try ctx.save()

        XCTAssertEqual(try ctx.fetch(TripEvent.fetchRequest()).count, 0)
        XCTAssertEqual(try ctx.fetch(TransitDetails.fetchRequest()).count, 0)
    }

    // MARK: — Enum bridge round-trips

    func test_eventCategory_bridgeRoundTrip() throws {
        let ev = TripEvent(context: ctx); ev.id = UUID(); ev.category = .flight
        try ctx.save()
        let fetched = try ctx.fetch(TripEvent.fetchRequest()).first!
        XCTAssertEqual(fetched.category, .flight)
        XCTAssertEqual(fetched.categoryRaw, "flight")
    }

    func test_memberRole_bridgeRoundTrip() throws {
        let m = TripMember(context: ctx); m.id = UUID(); m.appleUserID = "abc"; m.role = .viewer
        try ctx.save()
        let fetched = try ctx.fetch(TripMember.fetchRequest()).first!
        XCTAssertEqual(fetched.role, .viewer)
        XCTAssertFalse(fetched.isVirtual)
    }

    func test_isVirtual_emptyAppleUserID_returnsTrue() throws {
        let m = TripMember(context: ctx); m.id = UUID(); m.appleUserID = ""
        try ctx.save()
        XCTAssertTrue(m.isVirtual)
    }

    func test_expenseCategory_bridgeRoundTrip() throws {
        let e = TripExpense(context: ctx); e.id = UUID(); e.category = .food
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(TripExpense.fetchRequest()).first!.category, .food)
    }

    // MARK: — splitAmongJoined string bridge

    func test_splitAmongIDs_joinedStringRoundTrip() throws {
        let a = UUID(); let b = UUID()
        let e = TripExpense(context: ctx); e.id = UUID(); e.splitAmongIDs = [a, b]
        try ctx.save()
        let fetched = try ctx.fetch(TripExpense.fetchRequest()).first!
        XCTAssertEqual(Set(fetched.splitAmongIDs), Set([a, b]))
        XCTAssertFalse((fetched.splitAmongJoined ?? "").isEmpty)
    }

    // MARK: — Trip computed properties

    func test_trip_daysArray_sortedBySortOrder() throws {
        let trip = Trip(context: ctx); trip.id = UUID(); trip.name = "NYC"
        let d1 = TripDay(context: ctx); d1.id = UUID(); d1.sortOrder = 10; d1.trip = trip
        let d2 = TripDay(context: ctx); d2.id = UUID(); d2.sortOrder = 2;  d2.trip = trip
        try ctx.save()
        let fetched = try ctx.fetch(Trip.fetchRequest()).first!
        XCTAssertEqual(fetched.daysArray.map(\.sortOrder), [2, 10])
    }

    func test_trip_membersArray_includesVirtualMember() throws {
        let trip = Trip(context: ctx); trip.id = UUID(); trip.name = "Lisbon"
        let now = Date()
        let m1 = TripMember(context: ctx); m1.id = UUID(); m1.appleUserID = ""; m1.displayName = "Alex"; m1.joinedAt = now; m1.trip = trip
        let m2 = TripMember(context: ctx); m2.id = UUID(); m2.appleUserID = "real-id"; m2.displayName = "Bob"; m2.joinedAt = now; m2.trip = trip
        try ctx.save()
        let t = try ctx.fetch(Trip.fetchRequest()).first!
        XCTAssertEqual(t.membersArray.count, 2)
        XCTAssertTrue(t.membersArray.contains(where: { $0.isVirtual }))
        XCTAssertTrue(t.membersArray.contains(where: { !$0.isVirtual }))
    }
}
