//
//  CloudKitTripSharingBackend.swift
//  Daythread
//
//  The real, device-only implementation of TripSharingBackend, backed by
//  TripStoreMigrator + SharedZoneSharing instead of NSPersistentCloudKitContainer.share().
//
//  ⚠️ DEVICE-ONLY — NOT UNIT-TESTABLE
//  makeShare performs live CloudKit operations and cannot run on the
//  simulator (no iCloud account; CloudKit disabled there). Verified on-device.
//

import CloudKit
import CoreData
import os

struct CloudKitTripSharingBackend: TripSharingBackend {
    let container: CKContainer
    private let sharing: SharedZoneSharing
    private let migrator: TripStoreMigrator

    init(containerIdentifier: String = "iCloud.com.delonsampaio.daythread") {
        self.container = CKContainer(identifier: containerIdentifier)
        self.sharing = SharedZoneSharing(containerIdentifier: containerIdentifier)
        self.migrator = TripStoreMigrator.shared
    }

    func makeShare(for trip: Trip) async throws -> CKShare {
        guard let tripID = trip.id else { throw CocoaError(.fileNoSuchFile) }
        let title = trip.name

        // If already migrated and shared, fetch the existing share from the server.
        // This path is hit when managing/stopping an existing share.
        if trip.migration == .done || trip.objectID.persistentStore?.url?.lastPathComponent == "shared.sqlite" {
            // Try cache first, then fall back to a network fetch.
            if let cached = cachedShare(forTripID: tripID) { return cached }
            if let fetched = try await sharing.fetchShare(forTripID: tripID) { return fetched }
            throw CocoaError(.fileNoSuchFile)
        }

        // New share: migrate the trip and use the share returned directly from
        // makeZoneShare — no second network round-trip needed (avoids the window
        // where fetchShare returns nil immediately after zone creation).
        let (clone, freshShare) = try await migrator.migrate(trip, title: title)

        if let freshShare { return freshShare }

        // Resumed migration (.uploaded → .done): share was created in a prior run,
        // fetch it from the server now that the zone is established.
        guard let cloneID = clone.id else { throw CocoaError(.fileNoSuchFile) }
        if let cached = cachedShare(forTripID: cloneID) { return cached }
        if let fetched = try await sharing.fetchShare(forTripID: cloneID, attempts: 4) { return fetched }
        throw CocoaError(.fileNoSuchFile)
    }

    func existingShare(for trip: Trip) throws -> CKShare? {
        // Synchronous path: reconstruct from cached SyncState.shareSystemFields.
        guard let tripID = trip.id else { return nil }
        return cachedShare(forTripID: tripID)
    }

    func deleteShare(for trip: Trip) async throws {
        guard let tripID = trip.id else { return }
        try await sharing.deleteZone(forTripID: tripID)
    }

    // MARK: — Cache lookup

    private func cachedShare(forTripID tripID: UUID) -> CKShare? {
        let context = PersistenceController.shared.viewContext
        let zoneID = SharedZoneSharing.zoneID(for: tripID)
        let request = SyncState.fetchRequest()
        request.predicate = NSPredicate(format: "zoneName == %@ AND databaseScope == %@",
                                        zoneID.zoneName, "private")
        request.fetchLimit = 1
        guard let data = (try? context.fetch(request))?.first?.shareSystemFields else { return nil }
        guard let share = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKShare.self, from: data) else { return nil }
        return share
    }
}
