//
//  TripStoreTests.swift
//  DaythreadTests
//
//  Created by Delon Sampaio on 5/27/26.
//
//  Tests for the active-trip selection logic that lives in RootTabView.onChange(of: activeTrips).
//
//  Three scenarios we protect against:
//    1. Reinstall — CloudKit syncs data after onAppear fires with empty results
//       → store.activeTrip is still nil when trips finally arrive
//    2. Active trip deleted or archived → should fall back to another trip
//    3. Normal startup — activeTrip already valid → must not be overwritten
//

import XCTest
import SwiftData
@testable import Daythread

/// Mirror of the selection logic in RootTabView.onChange(of: activeTrips).
/// Keeping it here and in the view in sync is intentional — these tests define
/// the contract; if you ever extract this into TripStore, delete this helper.
@discardableResult
@MainActor
private func applyActiveTripSelection(store: TripStore, trips: [Trip]) -> Trip? {
    if store.activeTrip == nil {
        store.activeTrip = trips.first
    } else if let active = store.activeTrip,
              !trips.contains(where: { $0.id == active.id }) {
        store.activeTrip = trips.first
    }
    return store.activeTrip
}

@MainActor
final class TripStoreTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let schema = Schema([
            Trip.self, TripDay.self, TripEvent.self, TransitDetails.self,
            LodgingInfo.self, TripMember.self, TripDocument.self,
            TripExpense.self, PreTripTask.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        context = nil
        container = nil
    }

    // MARK: — Defaults

    func testActiveTripIsNilByDefault() {
        let store = TripStore()
        XCTAssertNil(store.activeTrip)
    }

    // MARK: — Reinstall / CloudKit-sync race

    /// onAppear fires with empty @Query results; CloudKit sync delivers trips later.
    /// store.activeTrip is still nil → selection must pick trips.first.
    func testReinstallRaceSetsActiveTripWhenPreviouslyNil() throws {
        let store = TripStore()
        XCTAssertNil(store.activeTrip, "precondition: no active trip yet")

        let paris  = Trip(name: "Paris",  destination: "France", startDate: .now, endDate: .now)
        let tokyo  = Trip(name: "Tokyo",  destination: "Japan",  startDate: .now, endDate: .now)
        context.insert(paris); context.insert(tokyo)
        try context.save()

        applyActiveTripSelection(store: store, trips: [paris, tokyo])

        XCTAssertEqual(store.activeTrip?.id, paris.id,
            "Reinstall race: first trip in list should become active")
    }

    func testReinstallRaceWithSingleTripSelectsThatTrip() throws {
        let store = TripStore()
        let solo = Trip(name: "Solo", destination: "Anywhere", startDate: .now, endDate: .now)
        context.insert(solo)
        try context.save()

        applyActiveTripSelection(store: store, trips: [solo])

        XCTAssertEqual(store.activeTrip?.id, solo.id)
    }

    func testReinstallRaceWithEmptyTripsLeavesNil() throws {
        let store = TripStore()
        applyActiveTripSelection(store: store, trips: [])
        XCTAssertNil(store.activeTrip)
    }

    // MARK: — Active trip deleted or archived

    /// The currently active trip is no longer in the query results (deleted/archived).
    /// Selection must fall back to the first remaining trip.
    func testFallsBackWhenActiveTripIsDeleted() throws {
        let store = TripStore()

        let tripA = Trip(name: "Amsterdam", destination: "Netherlands", startDate: .now, endDate: .now)
        let tripB = Trip(name: "Berlin",    destination: "Germany",     startDate: .now, endDate: .now)
        context.insert(tripA); context.insert(tripB)
        try context.save()

        store.activeTrip = tripA

        // tripA is deleted — it disappears from activeTrips query results
        context.delete(tripA)
        try context.save()

        applyActiveTripSelection(store: store, trips: [tripB])

        XCTAssertEqual(store.activeTrip?.id, tripB.id,
            "After active trip deletion, should fall back to first remaining trip")
    }

    func testFallsBackToNilWhenLastTripDeleted() throws {
        let store = TripStore()
        let only = Trip(name: "Only", destination: "Anywhere", startDate: .now, endDate: .now)
        context.insert(only)
        try context.save()

        store.activeTrip = only
        context.delete(only)
        try context.save()

        applyActiveTripSelection(store: store, trips: [])

        XCTAssertNil(store.activeTrip,
            "When all trips are deleted, activeTrip should become nil")
    }

    // MARK: — Normal launch (activeTrip already valid)

    /// If activeTrip is set and still exists in the query, selection must not change it.
    func testActiveTripRemainsStableWhenAlreadyValid() throws {
        let store = TripStore()

        let tripA = Trip(name: "Amsterdam", destination: "Netherlands", startDate: .now, endDate: .now)
        let tripB = Trip(name: "Berlin",    destination: "Germany",     startDate: .now, endDate: .now)
        context.insert(tripA); context.insert(tripB)
        try context.save()

        store.activeTrip = tripB   // user already chose tripB

        applyActiveTripSelection(store: store, trips: [tripA, tripB])

        XCTAssertEqual(store.activeTrip?.id, tripB.id,
            "activeTrip should not change when it is still valid in the list")
    }

    // MARK: — Pending share join resolution

    /// After accepting an invite, the joined trip eventually syncs in. When it
    /// appears, resolvePendingJoin must make it active and clear the pending name.
    func testResolvePendingJoin_matchingTrip_activatesAndClears() throws {
        let store = TripStore()
        let joined = Trip(name: "Shared", destination: "Italy", startDate: .now, endDate: .now)
        joined.cloudKitShareID = "share-rec-1"
        context.insert(joined)
        try context.save()

        store.pendingJoinShareRecordName = "share-rec-1"
        store.resolvePendingJoin(in: [joined])

        XCTAssertEqual(store.activeTrip?.id, joined.id)
        XCTAssertNil(store.pendingJoinShareRecordName, "pending name cleared once resolved")
    }

    /// If the joined trip hasn't synced yet, the pending name is retained so a
    /// later @Query update can resolve it; activeTrip is left untouched.
    func testResolvePendingJoin_noMatchYet_retainsPending() throws {
        let store = TripStore()
        let other = Trip(name: "Other", destination: "Spain", startDate: .now, endDate: .now)
        other.cloudKitShareID = "different-rec"
        context.insert(other)
        try context.save()

        store.pendingJoinShareRecordName = "share-rec-1"
        store.resolvePendingJoin(in: [other])

        XCTAssertNil(store.activeTrip)
        XCTAssertEqual(store.pendingJoinShareRecordName, "share-rec-1",
            "pending name retained until the trip syncs in")
    }

    /// With no pending join, resolvePendingJoin is a no-op and never changes activeTrip.
    func testResolvePendingJoin_nilPending_isNoOp() throws {
        let store = TripStore()
        let trip = Trip(name: "Solo", destination: "Anywhere", startDate: .now, endDate: .now)
        trip.cloudKitShareID = "rec-x"
        context.insert(trip)
        try context.save()

        store.pendingJoinShareRecordName = nil
        store.resolvePendingJoin(in: [trip])

        XCTAssertNil(store.activeTrip)
        XCTAssertNil(store.pendingJoinShareRecordName)
    }
}
