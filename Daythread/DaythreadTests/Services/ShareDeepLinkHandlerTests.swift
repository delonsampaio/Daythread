//
//  ShareDeepLinkHandlerTests.swift
//  DaythreadTests
//
//  Tests for ShareDeepLinkHandler.trip(forShareRecordName:in:) — the pure
//  function that maps an accepted CKShare record name back to the local Trip.
//

import XCTest
import CoreData
@testable import Daythread

@MainActor
final class ShareDeepLinkHandlerTests: XCTestCase {

    private var ctx: NSManagedObjectContext!

    override func setUpWithError() throws {
        ctx = PersistenceController(inMemory: true).viewContext
    }

    override func tearDownWithError() throws {
        ctx = nil
    }

    // MARK: — Helpers

    private func makeTrip(name: String = "Test", shareID: String? = nil) -> Trip {
        let t = Trip(context: ctx)
        t.id = UUID()
        t.name = name
        t.destination = "X"
        t.startDate = .now
        t.endDate = .now.addingTimeInterval(86400)
        t.gradientSeed = 0
        t.isArchived = false
        t.cloudKitShareID = shareID
        return t
    }

    // MARK: — Tests

    func test_exactMatch_returnsTrip() {
        let trip = makeTrip(name: "Paris", shareID: "ck-share-abc")
        let result = ShareDeepLinkHandler.trip(forShareRecordName: "ck-share-abc", in: [trip])
        XCTAssertEqual(result?.id, trip.id)
    }

    func test_noMatch_returnsNil() {
        let trip = makeTrip(name: "Paris", shareID: "ck-share-abc")
        let result = ShareDeepLinkHandler.trip(forShareRecordName: "ck-share-xyz", in: [trip])
        XCTAssertNil(result)
    }

    func test_emptyList_returnsNil() {
        let result = ShareDeepLinkHandler.trip(forShareRecordName: "ck-share-abc", in: [])
        XCTAssertNil(result)
    }

    func test_tripWithNilShareID_doesNotMatch() {
        let trip = makeTrip(name: "Tokyo", shareID: nil)
        let result = ShareDeepLinkHandler.trip(forShareRecordName: "ck-share-abc", in: [trip])
        XCTAssertNil(result)
    }

    func test_multipleTrips_returnsCorrectOne() {
        let paris = makeTrip(name: "Paris", shareID: "share-paris")
        let tokyo = makeTrip(name: "Tokyo", shareID: "share-tokyo")
        let result = ShareDeepLinkHandler.trip(forShareRecordName: "share-tokyo", in: [paris, tokyo])
        XCTAssertEqual(result?.id, tokyo.id)
    }

    func test_duplicateShareIDs_returnsFirstMatch() {
        let t1 = makeTrip(name: "A", shareID: "share-dup")
        let t2 = makeTrip(name: "B", shareID: "share-dup")
        let result = ShareDeepLinkHandler.trip(forShareRecordName: "share-dup", in: [t1, t2])
        XCTAssertEqual(result?.id, t1.id)
    }

    func test_emptyRecordName_doesNotMatchNonEmptyShareID() {
        let trip = makeTrip(name: "Berlin", shareID: "share-abc")
        let result = ShareDeepLinkHandler.trip(forShareRecordName: "", in: [trip])
        XCTAssertNil(result)
    }

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
