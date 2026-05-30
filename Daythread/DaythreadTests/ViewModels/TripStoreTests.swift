//
//  TripStoreTests.swift
//  DaythreadTests
//
//  Tests for the active-trip selection logic in RootTabView.onChange(of: activeTrips).
//

import XCTest
import CoreData
@testable import Daythread

/// Mirror of the selection logic in RootTabView.onChange(of: activeTrips.map(\.id)).
@discardableResult
@MainActor
private func applyActiveTripSelection(store: TripStore, trips: [Trip]) -> Trip? {
    if store.activeTrip == nil {
        store.activeTrip = trips.first
    } else if let active = store.activeTrip,
              // Guard: managedObjectContext is nil for deleted objects after save;
              // accessing @NSManaged id on such objects crashes with
              // NSObjectInaccessibleException. || short-circuits so id is safe.
              active.managedObjectContext == nil ||
              !trips.contains(where: { $0.id == active.id }) {
        store.activeTrip = trips.first
    }
    return store.activeTrip
}

@MainActor
final class TripStoreTests: XCTestCase {

    private var ctx: NSManagedObjectContext!

    override func setUp() async throws {
        ctx = PersistenceController(inMemory: true).viewContext
    }

    override func tearDown() async throws {
        ctx = nil
    }

    // MARK: — Helpers

    private func makeTrip(name: String, shareID: String? = nil) -> Trip {
        let t = Trip(context: ctx)
        t.id = UUID()
        t.name = name
        t.destination = "Anywhere"
        t.startDate = .now
        t.endDate = .now
        t.gradientSeed = 0
        t.isArchived = false
        t.cloudKitShareID = shareID
        return t
    }

    // MARK: — Defaults

    func testActiveTripIsNilByDefault() {
        let store = TripStore()
        XCTAssertNil(store.activeTrip)
    }

    // MARK: — Reinstall / CloudKit-sync race

    func testReinstallRaceSetsActiveTripWhenPreviouslyNil() throws {
        let store = TripStore()
        let paris = makeTrip(name: "Paris")
        let tokyo = makeTrip(name: "Tokyo")
        try ctx.save()

        applyActiveTripSelection(store: store, trips: [paris, tokyo])

        XCTAssertEqual(store.activeTrip?.id, paris.id)
    }

    func testReinstallRaceWithSingleTripSelectsThatTrip() throws {
        let store = TripStore()
        let solo = makeTrip(name: "Solo")
        try ctx.save()

        applyActiveTripSelection(store: store, trips: [solo])

        XCTAssertEqual(store.activeTrip?.id, solo.id)
    }

    func testReinstallRaceWithEmptyTripsLeavesNil() {
        let store = TripStore()
        applyActiveTripSelection(store: store, trips: [])
        XCTAssertNil(store.activeTrip)
    }

    // MARK: — Active trip deleted or archived

    func testFallsBackWhenActiveTripIsDeleted() throws {
        let store = TripStore()
        let tripA = makeTrip(name: "Amsterdam")
        let tripB = makeTrip(name: "Berlin")
        try ctx.save()

        store.activeTrip = tripA
        ctx.delete(tripA)
        try ctx.save()

        applyActiveTripSelection(store: store, trips: [tripB])

        XCTAssertEqual(store.activeTrip?.id, tripB.id)
    }

    func testFallsBackToNilWhenLastTripDeleted() throws {
        let store = TripStore()
        let only = makeTrip(name: "Only")
        try ctx.save()

        store.activeTrip = only
        ctx.delete(only)
        try ctx.save()

        applyActiveTripSelection(store: store, trips: [])

        XCTAssertNil(store.activeTrip)
    }

    // MARK: — Normal launch

    func testActiveTripRemainsStableWhenAlreadyValid() throws {
        let store = TripStore()
        let tripA = makeTrip(name: "Amsterdam")
        let tripB = makeTrip(name: "Berlin")
        try ctx.save()

        store.activeTrip = tripB
        applyActiveTripSelection(store: store, trips: [tripA, tripB])

        XCTAssertEqual(store.activeTrip?.id, tripB.id)
    }

    // MARK: — Pending share join resolution

    func testResolvePendingJoin_matchingTrip_activatesAndClears() throws {
        let store = TripStore()
        let joined = makeTrip(name: "Shared", shareID: "share-rec-1")
        try ctx.save()

        store.pendingJoinShareRecordName = "share-rec-1"
        store.resolvePendingJoin(in: [joined])

        XCTAssertEqual(store.activeTrip?.id, joined.id)
        XCTAssertNil(store.pendingJoinShareRecordName)
    }

    func testResolvePendingJoin_noMatchYet_retainsPending() throws {
        let store = TripStore()
        let other = makeTrip(name: "Other", shareID: "different-rec")
        try ctx.save()

        store.pendingJoinShareRecordName = "share-rec-1"
        store.resolvePendingJoin(in: [other])

        XCTAssertNil(store.activeTrip)
        XCTAssertEqual(store.pendingJoinShareRecordName, "share-rec-1")
    }

    func testResolvePendingJoin_nilPending_isNoOp() throws {
        let store = TripStore()
        let trip = makeTrip(name: "Solo", shareID: "rec-x")
        try ctx.save()

        store.pendingJoinShareRecordName = nil
        store.resolvePendingJoin(in: [trip])

        XCTAssertNil(store.activeTrip)
        XCTAssertNil(store.pendingJoinShareRecordName)
    }
}
