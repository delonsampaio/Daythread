//
//  ShareDeepLinkHandlerTests.swift
//  DaythreadTests
//
//  Tests for ShareDeepLinkHandler.trip(forShareRecordName:in:) — the pure
//  function that maps an accepted CKShare record name back to the local Trip
//  so DaythreadApp can switch store.activeTrip after a share is accepted.
//

import XCTest
import SwiftData
@testable import Daythread

private let dlSchema = Schema([
    Trip.self, TripDay.self, TripEvent.self, TransitDetails.self,
    LodgingInfo.self, TripMember.self, TripDocument.self,
    TripExpense.self, PreTripTask.self
])

@MainActor
final class ShareDeepLinkHandlerTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(schema: dlSchema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: dlSchema, configurations: [config])
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    // MARK: — Helpers

    private func makeTrip(name: String = "Test", shareID: String? = nil) -> Trip {
        let t = Trip(name: name, destination: "X",
                     startDate: .now, endDate: .now.addingTimeInterval(86400))
        t.cloudKitShareID = shareID
        context.insert(t)
        return t
    }

    // MARK: — Tests

    // Exact match on cloudKitShareID → returns the trip.
    func test_exactMatch_returnsTrip() {
        let trip = makeTrip(name: "Paris", shareID: "ck-share-abc")

        let result = ShareDeepLinkHandler.trip(forShareRecordName: "ck-share-abc", in: [trip])

        XCTAssertEqual(result?.id, trip.id)
    }

    // No trip has the given share record name → returns nil.
    func test_noMatch_returnsNil() {
        let trip = makeTrip(name: "Paris", shareID: "ck-share-abc")

        let result = ShareDeepLinkHandler.trip(forShareRecordName: "ck-share-xyz", in: [trip])

        XCTAssertNil(result)
    }

    // Empty trip list → returns nil without crashing.
    func test_emptyList_returnsNil() {
        let result = ShareDeepLinkHandler.trip(forShareRecordName: "ck-share-abc", in: [])
        XCTAssertNil(result)
    }

    // Trip with nil cloudKitShareID never matches any record name.
    func test_tripWithNilShareID_doesNotMatch() {
        let trip = makeTrip(name: "Tokyo", shareID: nil)

        let result = ShareDeepLinkHandler.trip(forShareRecordName: "ck-share-abc", in: [trip])

        XCTAssertNil(result)
    }

    // Multiple trips — returns the one with the matching share ID, not others.
    func test_multipleTrips_returnsCorrectOne() {
        let paris = makeTrip(name: "Paris", shareID: "share-paris")
        let tokyo = makeTrip(name: "Tokyo", shareID: "share-tokyo")

        let result = ShareDeepLinkHandler.trip(forShareRecordName: "share-tokyo", in: [paris, tokyo])

        XCTAssertEqual(result?.id, tokyo.id)
    }

    // Duplicate share IDs (shouldn't happen in practice) — returns first match.
    func test_duplicateShareIDs_returnsFirstMatch() {
        let t1 = makeTrip(name: "A", shareID: "share-dup")
        let t2 = makeTrip(name: "B", shareID: "share-dup")

        let result = ShareDeepLinkHandler.trip(forShareRecordName: "share-dup", in: [t1, t2])

        XCTAssertEqual(result?.id, t1.id)
    }

    // Empty record name never matches, even for trips that have a share ID.
    func test_emptyRecordName_doesNotMatchNonEmptyShareID() {
        let trip = makeTrip(name: "Berlin", shareID: "share-abc")

        let result = ShareDeepLinkHandler.trip(forShareRecordName: "", in: [trip])

        XCTAssertNil(result)
    }

    // Only the trip whose cloudKitShareID matches — others with nil are ignored.
    func test_mixedTrips_onlyMatchesShareIDHolder() {
        let shared    = makeTrip(name: "Shared",    shareID: "share-xyz")
        let unshared1 = makeTrip(name: "Unshared1", shareID: nil)
        let unshared2 = makeTrip(name: "Unshared2", shareID: nil)

        let result = ShareDeepLinkHandler.trip(
            forShareRecordName: "share-xyz",
            in: [unshared1, shared, unshared2]
        )

        XCTAssertEqual(result?.id, shared.id)
    }
}
