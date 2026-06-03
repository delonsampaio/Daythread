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
import os

struct CloudKitTripSharingBackend: TripSharingBackend {
    let container: CKContainer
    private let persistentContainer: NSPersistentCloudKitContainer

    init(persistentContainer: NSPersistentCloudKitContainer = PersistenceController.shared.cloudKitContainer,
         containerIdentifier: String = "iCloud.com.delonsampaio.daythread") {
        self.persistentContainer = persistentContainer
        self.container = CKContainer(identifier: containerIdentifier)
    }

    func makeShare(for trip: Trip) async throws -> CKShare {
        // objectID is the only thing safe to read off the caller's context here.
        let objectID = trip.objectID

        // If the trip's object graph already has a share (e.g. the local
        // cloudKitShareID was cleared by stopSharing but CloudKit/Core Data still
        // holds share metadata), reuse it. Calling share([trip], to:) again on an
        // already-shared record hangs, which froze the "Invite People" flow.
        if let existing = try persistentContainer.fetchShares(matching: [objectID])[objectID] {
            daythreadLog.log("makeShare: reusing existing share")
            return existing
        }

        // share([trip], to:) grabs the persistent-store-coordinator lock and must
        // wait behind the foreground export backlog (NSPCKC exports in-foreground
        // because the `processing` background mode was removed for App Store
        // validation). Called on the viewContext that wait FROZE the main thread
        // until the backlog cleared. Resolve the trip on a BACKGROUND context and
        // share that object so the lock-wait happens off the main thread — the UI
        // stays responsive and share() still completes normally.
        let bgContext = persistentContainer.newBackgroundContext()
        let (bgTrip, title) = try await bgContext.perform { () -> (Trip, String) in
            guard let t = try bgContext.existingObject(with: objectID) as? Trip else {
                throw CocoaError(.managedObjectReferentialIntegrity)
            }
            // KVC read — Trip's typed `name` accessor is MainActor-isolated and this
            // closure runs on the background context's queue.
            let name = (t.value(forKey: "name") as? String) ?? ""
            return (t, name)
        }
        daythreadLog.log("makeShare: calling NSPCKC share() on background context…")
        let (_, share, _) = try await persistentContainer.share([bgTrip], to: nil)
        daythreadLog.log("makeShare: share() returned")
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        return share
    }

    func existingShare(for trip: Trip) throws -> CKShare? {
        // fetchShares reads the share metadata Core Data already holds for the
        // trip's object graph — no network round-trip required.
        try persistentContainer.fetchShares(matching: [trip.objectID])[trip.objectID]
    }
}
