//
//  CloudKitServiceTests.swift
//  DaythreadTests
//
//  Tests CloudKitService's share orchestration logic with an injected stub
//  backend. The real CloudKit network calls live in CloudKitTripSharingBackend
//  (device-only); here we verify branching, model mutation, and error handling.
//

import XCTest
import CloudKit
import CoreData
@testable import Daythread

// MARK: — Stub backend

private final class StubSharingBackend: TripSharingBackend {
    var makeShareCallCount = 0
    var shareToReturn: CKShare
    var errorToThrow: Error?
    let container = CKContainer.default()

    init(share: CKShare) { self.shareToReturn = share }

    func makeShare(for trip: Trip) async throws -> CKShare {
        makeShareCallCount += 1
        if let error = errorToThrow { throw error }
        return shareToReturn
    }
}

private struct StubError: Error {}

@MainActor
final class CloudKitServiceTests: XCTestCase {

    private var ctx: NSManagedObjectContext!

    override func setUpWithError() throws {
        ctx = PersistenceController(inMemory: true).viewContext
    }

    override func tearDownWithError() throws {
        ctx = nil
    }

    // MARK: — Helpers

    private func makeTrip(shareID: String? = nil) -> Trip {
        let t = Trip(context: ctx)
        t.id = UUID()
        t.name = "Paris"
        t.destination = "France"
        t.startDate = .now
        t.endDate = .now.addingTimeInterval(86400)
        t.gradientSeed = 0
        t.isArchived = false
        t.cloudKitShareID = shareID
        return t
    }

    private func makeShare() -> CKShare {
        let root = CKRecord(recordType: "Trip")
        return CKShare(rootRecord: root)
    }

    // MARK: — Tests

    func test_shareTrip_setsCloudKitShareIDFromShareRecordName() async {
        let share = makeShare()
        let backend = StubSharingBackend(share: share)
        let service = CloudKitService(backend: backend)
        let trip = makeTrip(shareID: nil)

        let result = await service.shareTrip(trip, modelContext: ctx)

        XCTAssertEqual(trip.cloudKitShareID, share.recordID.recordName)
        XCTAssertEqual(result?.recordID.recordName, share.recordID.recordName)
        XCTAssertTrue(service.isSharing)
        XCTAssertNil(service.errorMessage)
    }

    func test_shareTrip_alreadyShared_doesNotCallBackend() async {
        let backend = StubSharingBackend(share: makeShare())
        let service = CloudKitService(backend: backend)
        let trip = makeTrip(shareID: "existing-share-id")

        _ = await service.shareTrip(trip, modelContext: ctx)

        XCTAssertEqual(backend.makeShareCallCount, 0)
        XCTAssertEqual(trip.cloudKitShareID, "existing-share-id")
    }

    func test_shareTrip_backendThrows_setsErrorAndLeavesTripUnshared() async {
        let backend = StubSharingBackend(share: makeShare())
        backend.errorToThrow = StubError()
        let service = CloudKitService(backend: backend)
        let trip = makeTrip(shareID: nil)

        let result = await service.shareTrip(trip, modelContext: ctx)

        XCTAssertNil(result)
        XCTAssertNil(trip.cloudKitShareID)
        XCTAssertNotNil(service.errorMessage)
        XCTAssertFalse(service.isSharing)
    }

    func test_stopSharing_clearsShareIDAndFlag() async {
        let backend = StubSharingBackend(share: makeShare())
        let service = CloudKitService(backend: backend)
        let trip = makeTrip(shareID: "some-share-id")

        service.stopSharing(trip, modelContext: ctx)

        XCTAssertNil(trip.cloudKitShareID)
        XCTAssertFalse(service.isSharing)
    }

    func test_shareTrip_callsBackendExactlyOnce() async {
        let backend = StubSharingBackend(share: makeShare())
        let service = CloudKitService(backend: backend)
        let trip = makeTrip(shareID: nil)

        _ = await service.shareTrip(trip, modelContext: ctx)

        XCTAssertEqual(backend.makeShareCallCount, 1)
    }
}
