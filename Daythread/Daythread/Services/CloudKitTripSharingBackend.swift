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
        let title = (trip.value(forKey: "name") as? String) ?? ""

        // If the trip's object graph already has a share (e.g. the local
        // cloudKitShareID was cleared by stopSharing but CloudKit/Core Data still
        // holds share metadata), reuse it. Calling share([trip], to:) again on an
        // already-shared record hangs, which froze the "Invite People" flow.
        if let existing = try persistentContainer.fetchShares(matching: [objectID])[objectID] {
            daythreadLog.log("makeShare: reusing existing share")
            return existing
        }

        // CRITICAL: this module is MainActor-by-default, so makeShare runs on the
        // MAIN actor — awaiting share() here kept its internal main-queue work on the
        // main thread and deadlocked the UI even on an idle container. Run share() on
        // a fully DETACHED task so it physically cannot touch the main thread; the
        // share it creates is then re-fetched on the calling context.
        let pc = persistentContainer
        daythreadLog.log("makeShare: calling NSPCKC share() on a detached task…")
        try await Task.detached(priority: .userInitiated) {
            let bg = pc.newBackgroundContext()
            let obj = try bg.existingObject(with: objectID)
            _ = try await pc.share([obj], to: nil)
        }.value
        daythreadLog.log("makeShare: share() detached returned")

        guard let share = try persistentContainer.fetchShares(matching: [objectID])[objectID] else {
            throw CocoaError(.fileNoSuchFile)
        }
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        return share
    }

    func existingShare(for trip: Trip) throws -> CKShare? {
        // fetchShares reads the share metadata Core Data already holds for the
        // trip's object graph — no network round-trip required.
        try persistentContainer.fetchShares(matching: [trip.objectID])[trip.objectID]
    }
}
