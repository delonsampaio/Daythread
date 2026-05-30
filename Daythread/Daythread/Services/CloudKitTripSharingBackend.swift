//
//  CloudKitTripSharingBackend.swift
//  Daythread
//
//  The real, device-only implementation of TripSharingBackend.
//
//  ⚠️ DEVICE-ONLY — NOT UNIT-TESTABLE
//  This code performs live CloudKit network operations. It cannot run on the
//  simulator (the app builds its ModelContainer with cloudKitDatabase: .none on
//  the simulator, and there is no signed-in iCloud account there). All behaviour
//  here must be verified on a physical device signed into iCloud, with the
//  CloudKit container provisioned in Signing & Capabilities → iCloud → CloudKit.
//
//  ⚠️ KNOWN ARCHITECTURAL LIMITATION
//  SwiftData's ModelContainer wraps NSPersistentCloudKitContainer but does NOT
//  expose a first-class sharing API (no equivalent of
//  NSPersistentCloudKitContainer.share(_:to:)). This backend therefore creates a
//  standalone CKShare on a dedicated zone so the system invite sheet and the
//  join deep-link can be exercised end-to-end. Associating the shared CKShare
//  with the actual SwiftData record graph (so co-editors see live trip data) is
//  the remaining on-device work and may require dropping to the persistent
//  coordinator or migrating trip sharing to NSPersistentCloudKitContainer.
//  See BACKLOG.md → "Co-editing v1.0 — Implementation Plan".
//

import CloudKit

struct CloudKitTripSharingBackend: TripSharingBackend {
    let container: CKContainer
    private let zoneName = "DaythreadZone"

    init(containerIdentifier: String = "iCloud.com.delonsampaio.daythread") {
        self.container = CKContainer(identifier: containerIdentifier)
    }

    func makeShare(for trip: Trip) async throws -> CKShare {
        let database = container.privateCloudDatabase

        // Ensure the custom zone exists (idempotent — re-saving an existing zone
        // is a no-op that returns the same zone).
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await database.save(zone)

        // Root record representing the trip, keyed by the trip's stable UUID so
        // the same trip always maps to the same CloudKit record.
        let rootRecordID = CKRecord.ID(recordName: trip.id.uuidString, zoneID: zoneID)
        let rootRecord = CKRecord(recordType: "Trip", recordID: rootRecordID)
        rootRecord["name"] = trip.name as CKRecordValue

        // The share itself — invite-only, titled with the trip name.
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = trip.name as CKRecordValue
        share.publicPermission = .none

        let result = try await database.modifyRecords(
            saving: [rootRecord, share],
            deleting: []
        )

        for (_, saveResult) in result.saveResults {
            if case .failure(let error) = saveResult { throw error }
        }
        return share
    }
}
