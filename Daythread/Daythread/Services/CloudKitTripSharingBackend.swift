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

        // Trip is already in shared.sqlite and still has an active share — fetch it.
        if (trip.migration == .done || trip.objectID.persistentStore?.url?.lastPathComponent == "shared.sqlite")
            && trip.cloudKitShareID != nil {
            if let cached = cachedShare(forTripID: tripID) { return cached }
            if let fetched = try await sharing.fetchShare(forTripID: tripID) { return fetched }
            throw CocoaError(.fileNoSuchFile)
        }

        // Trip is in shared.sqlite but cloudKitShareID is nil — this happens when
        // the owner stopped sharing and then wants to re-share the same trip.
        // The object graph is already in the shared store; we just need a new zone+share.
        // Reset migration to .cloned so migrate() re-runs Phase 2 (create zone + upload).
        if trip.objectID.persistentStore?.url?.lastPathComponent == "shared.sqlite",
           trip.cloudKitShareID == nil {
            trip.migration = .cloned
            // Clear stale system fields so uploadClone assigns the new zone's IDs.
            let context = PersistenceController.shared.viewContext
            clearSystemFields(for: trip, context: context)
            try? context.save()
            daythreadLog.log("CloudKitTripSharingBackend: re-sharing existing shared-store trip — reset to .cloned")
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

    // MARK: — Re-share helpers

    /// Clears ckSystemFields on all objects in `trip`'s graph so uploadClone
    /// builds fresh CKRecords in the new zone rather than reusing stale ones
    /// pointing at the deleted zone.
    private func clearSystemFields(for trip: Trip, context: NSManagedObjectContext) {
        var objects: [NSManagedObject] = [trip]
        for day in trip.daysArray {
            objects.append(day)
            for event in day.eventsArray {
                objects.append(event)
                if let td = event.transitDetails { objects.append(td) }
            }
        }
        objects += trip.documentsArray as [NSManagedObject]
        objects += trip.expensesArray  as [NSManagedObject]
        objects += trip.lodgingArray   as [NSManagedObject]
        objects += trip.membersArray   as [NSManagedObject]
        objects += trip.preTripTasksArray as [NSManagedObject]
        for obj in objects {
            obj.setValue(nil, forKey: "ckSystemFields")
        }
    }

    // MARK: — Cache lookup

    private func cachedShare(forTripID tripID: UUID) -> CKShare? {
        let context = PersistenceController.shared.viewContext
        let zoneID = SharedZoneSharing.zoneID(for: tripID)
        let request = SyncState.fetchRequest()
        // Owners have databaseScope "private"; participants have "shared" (the zone
        // lives in the owner's private DB and is accessible to participants via the
        // shared DB). Both need to be checked so the cache works for participants too.
        request.predicate = NSPredicate(
            format: "zoneName == %@ AND (databaseScope == %@ OR databaseScope == %@)",
            zoneID.zoneName, "private", "shared"
        )
        request.fetchLimit = 1
        guard let data = (try? context.fetch(request))?.first?.shareSystemFields else { return nil }
        guard let share = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKShare.self, from: data) else { return nil }
        return share
    }
}
