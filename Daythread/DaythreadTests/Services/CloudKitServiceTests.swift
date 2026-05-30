//
//  CloudKitServiceTests.swift
//  DaythreadTests
//
//  Tests CloudKitService's share orchestration logic with an injected stub
//  backend (TripSharingBackend). The real CloudKit network calls live in
//  CloudKitTripSharingBackend, which is device-only; here we verify the
//  service's branching, model mutation, and error handling — not CloudKit.
//

import XCTest
import CloudKit
import SwiftData
@testable import Daythread

private let ckSchema = Schema([
    Trip.self, TripDay.self, TripEvent.self, TransitDetails.self,
    LodgingInfo.self, TripMember.self, TripDocument.self,
    TripExpense.self, PreTripTask.self
])

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

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(schema: ckSchema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: ckSchema, configurations: [config])
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    // MARK: — Helpers

    private func makeTrip(shareID: String? = nil) -> Trip {
        let t = Trip(name: "Paris", destination: "France",
                     startDate: .now, endDate: .now.addingTimeInterval(86400))
        t.cloudKitShareID = shareID
        context.insert(t)
        return t
    }

    private func makeShare() -> CKShare {
        let root = CKRecord(recordType: "Trip")
        return CKShare(rootRecord: root)
    }

    // MARK: — Tests

    // Sharing an unshared trip stamps the share's record name onto the trip.
    func test_shareTrip_setsCloudKitShareIDFromShareRecordName() async {
        let share = makeShare()
        let backend = StubSharingBackend(share: share)
        let service = CloudKitService(backend: backend)
        let trip = makeTrip(shareID: nil)

        let result = await service.shareTrip(trip, modelContext: context)

        XCTAssertEqual(trip.cloudKitShareID, share.recordID.recordName)
        XCTAssertEqual(result?.recordID.recordName, share.recordID.recordName)
        XCTAssertTrue(service.isSharing)
        XCTAssertNil(service.errorMessage)
    }

    // An already-shared trip does NOT hit the backend again — it reuses the share.
    func test_shareTrip_alreadyShared_doesNotCallBackend() async {
        let backend = StubSharingBackend(share: makeShare())
        let service = CloudKitService(backend: backend)
        let trip = makeTrip(shareID: "existing-share-id")

        _ = await service.shareTrip(trip, modelContext: context)

        XCTAssertEqual(backend.makeShareCallCount, 0)
        XCTAssertEqual(trip.cloudKitShareID, "existing-share-id")
    }

    // Backend failure surfaces an error message and leaves the trip unshared.
    func test_shareTrip_backendThrows_setsErrorAndLeavesTripUnshared() async {
        let backend = StubSharingBackend(share: makeShare())
        backend.errorToThrow = StubError()
        let service = CloudKitService(backend: backend)
        let trip = makeTrip(shareID: nil)

        let result = await service.shareTrip(trip, modelContext: context)

        XCTAssertNil(result)
        XCTAssertNil(trip.cloudKitShareID)
        XCTAssertNotNil(service.errorMessage)
        XCTAssertFalse(service.isSharing)
    }

    // Stop sharing clears the share ID and the sharing flag.
    func test_stopSharing_clearsShareIDAndFlag() async {
        let backend = StubSharingBackend(share: makeShare())
        let service = CloudKitService(backend: backend)
        let trip = makeTrip(shareID: "some-share-id")

        service.stopSharing(trip, modelContext: context)

        XCTAssertNil(trip.cloudKitShareID)
        XCTAssertFalse(service.isSharing)
    }

    // The backend is called exactly once for a fresh share.
    func test_shareTrip_callsBackendExactlyOnce() async {
        let backend = StubSharingBackend(share: makeShare())
        let service = CloudKitService(backend: backend)
        let trip = makeTrip(shareID: nil)

        _ = await service.shareTrip(trip, modelContext: context)

        XCTAssertEqual(backend.makeShareCallCount, 1)
    }
}
