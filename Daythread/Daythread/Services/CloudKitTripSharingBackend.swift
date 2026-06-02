//
//  CloudKitTripSharingBackend.swift
//  Daythread
//
//  The real, device-only implementation of TripSharingBackend, backed by
//  NSPersistentCloudKitContainer's native sharing (share(_:to:)).
//
//  ⚠️ DEVICE-ONLY — NOT UNIT-TESTABLE
//  share(_:to:) performs live CloudKit operations and cannot run on the
//  simulator (no iCloud account; CloudKit disabled there). Verified on-device.
//

import CloudKit
import CoreData

struct CloudKitTripSharingBackend: TripSharingBackend {
    let container: CKContainer
    private let persistentContainer: NSPersistentCloudKitContainer

    init(persistentContainer: NSPersistentCloudKitContainer = PersistenceController.shared.cloudKitContainer,
         containerIdentifier: String = "iCloud.com.delonsampaio.daythread") {
        self.persistentContainer = persistentContainer
        self.container = CKContainer(identifier: containerIdentifier)
    }

    func makeShare(for trip: Trip) async throws -> CKShare {
        // If the trip's object graph already has a share (e.g. the local
        // cloudKitShareID was cleared by stopSharing but CloudKit/Core Data still
        // holds share metadata), reuse it. Calling share([trip], to:) again on an
        // already-shared record hangs, which froze the "Invite People" flow.
        if let existing = try persistentContainer.fetchShares(matching: [trip.objectID])[trip.objectID] {
            return existing
        }
        let (_, share, _) = try await persistentContainer.share([trip], to: nil)
        share[CKShare.SystemFieldKey.title] = trip.name as CKRecordValue
        return share
    }

    func existingShare(for trip: Trip) throws -> CKShare? {
        // fetchShares reads the share metadata Core Data already holds for the
        // trip's object graph — no network round-trip required.
        try persistentContainer.fetchShares(matching: [trip.objectID])[trip.objectID]
    }
}
