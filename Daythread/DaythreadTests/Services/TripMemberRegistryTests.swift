//
//  TripMemberRegistryTests.swift
//  DaythreadTests
//
//  Tests the upsert logic that registers the current user as a real (non-virtual)
//  trip member so co-editors see real names + roles in Group Sync.
//

import XCTest
import CoreData
@testable import Daythread

@MainActor
final class TripMemberRegistryTests: XCTestCase {

    private var ctx: NSManagedObjectContext!

    override func setUpWithError() throws {
        ctx = PersistenceController(inMemory: true).viewContext
    }

    override func tearDownWithError() throws {
        ctx = nil
    }

    private func makeTrip() -> Trip {
        let t = Trip(context: ctx); t.id = UUID(); t.name = "Paris"; return t
    }

    func test_upsert_createsNonVirtualMemberLinkedToTrip() throws {
        let trip = makeTrip()

        let m = TripMemberRegistry.upsertCurrentUser(
            in: trip, appleUserID: "uid-1", displayName: "Delon", role: .admin, context: ctx
        )
        try ctx.save()

        XCTAssertEqual(trip.membersArray.count, 1)
        XCTAssertEqual(m.displayName, "Delon")
        XCTAssertEqual(m.role, .admin)
        XCTAssertFalse(m.isVirtual)
        XCTAssertEqual(m.trip?.id, trip.id)
    }

    func test_upsert_sameUserTwice_updatesInsteadOfDuplicating() throws {
        let trip = makeTrip()
        _ = TripMemberRegistry.upsertCurrentUser(
            in: trip, appleUserID: "uid-1", displayName: "Delon", role: .editor, context: ctx
        )
        try ctx.save()

        let m2 = TripMemberRegistry.upsertCurrentUser(
            in: trip, appleUserID: "uid-1", displayName: "Delon S.", role: .admin, context: ctx
        )
        try ctx.save()

        XCTAssertEqual(trip.membersArray.count, 1)
        XCTAssertEqual(m2.displayName, "Delon S.")
        XCTAssertEqual(m2.role, .admin)
    }

    func test_upsert_differentUsers_createSeparateMembers() throws {
        let trip = makeTrip()
        _ = TripMemberRegistry.upsertCurrentUser(
            in: trip, appleUserID: "uid-1", displayName: "Delon", role: .admin, context: ctx
        )
        _ = TripMemberRegistry.upsertCurrentUser(
            in: trip, appleUserID: "uid-2", displayName: "Sam", role: .editor, context: ctx
        )
        try ctx.save()

        XCTAssertEqual(trip.membersArray.count, 2)
    }

    /// Virtual (expense-only) members have an empty appleUserID — the upsert must
    /// never match them, or registering a real user would hijack a virtual member.
    func test_upsert_doesNotMatchVirtualMembers() throws {
        let trip = makeTrip()
        let virtual = TripMember(context: ctx)
        virtual.id = UUID(); virtual.appleUserID = ""; virtual.displayName = "Cash Friend"
        virtual.joinedAt = Date(); virtual.trip = trip
        try ctx.save()

        _ = TripMemberRegistry.upsertCurrentUser(
            in: trip, appleUserID: "uid-1", displayName: "Delon", role: .admin, context: ctx
        )
        try ctx.save()

        XCTAssertEqual(trip.membersArray.count, 2)
        XCTAssertTrue(trip.membersArray.contains { $0.isVirtual })
        XCTAssertTrue(trip.membersArray.contains { $0.appleUserID == "uid-1" })
    }
}
