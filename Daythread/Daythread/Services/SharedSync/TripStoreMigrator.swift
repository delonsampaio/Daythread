//
//  TripStoreMigrator.swift
//  Daythread
//
//  Crash-safe migration of a Trip's full object graph from the NSPCKC private
//  store into the custom-synced shared store. Three-phase:
//    1. cloneGraph  — deep-copy into shared store (this file, Task 3.1)
//    2. upload      — push to custom CloudKit zone (Task 3.2)
//    3. purge       — delete NSPCKC originals ONLY after upload confirmed (Task 3.2)
//
//  SAFETY: NSPCKC deletes propagate only within com.apple.coredata.cloudkit.zone.
//  Records uploaded to our custom Zone-<tripUUID> are in a completely separate
//  zone that NSPCKC does not manage, so purging the NSPCKC copies cannot touch
//  the already-uploaded custom-zone records.
//

import CloudKit
import CoreData
import os

@MainActor
final class TripStoreMigrator {
    static let shared = TripStoreMigrator()
    private init() {}

    // MARK: — Phase 1: Clone

    /// Deep-copies the Trip's full object graph into shared.sqlite.
    /// The original NSPCKC-store objects are left untouched.
    /// Returns the clone with migration state .cloned, already saved.
    /// Throws if the shared store cannot be located or the save fails.
    func cloneGraph(_ trip: Trip) throws -> Trip {
        let context = PersistenceController.shared.viewContext
        guard let sharedStore = sharedStore(in: context) else {
            throw MigrationError.sharedStoreNotFound
        }

        // Prefetch the full graph so relationship traversal doesn't fault
        // across actor boundaries or produce partial copies.
        let prefetchRequest = Trip.fetchRequest()
        prefetchRequest.predicate = NSPredicate(format: "self == %@", trip)
        prefetchRequest.relationshipKeyPathsForPrefetching = [
            "days", "days.events", "days.events.transitDetails",
            "documents", "expenses", "lodging", "members", "preTripTasks"
        ]
        prefetchRequest.returnsObjectsAsFaults = false
        _ = try context.fetch(prefetchRequest)

        // Clone Trip.
        let clonedTrip = Trip(context: context)
        context.assign(clonedTrip, to: sharedStore)
        copyTripAttributes(from: trip, to: clonedTrip)
        clonedTrip.ckRecordName = UUID().uuidString   // fresh identity
        clonedTrip.ckSystemFields = nil
        clonedTrip.migration = .cloned

        // Clone TripDay + TripEvent (+ TransitDetails if present).
        for day in trip.daysArray {
            let clonedDay = TripDay(context: context)
            context.assign(clonedDay, to: sharedStore)
            copyDayAttributes(from: day, to: clonedDay)
            clonedDay.ckRecordName = UUID().uuidString
            clonedDay.ckSystemFields = nil
            clonedDay.trip = clonedTrip

            for event in day.eventsArray {
                let clonedEvent = TripEvent(context: context)
                context.assign(clonedEvent, to: sharedStore)
                copyEventAttributes(from: event, to: clonedEvent)
                clonedEvent.ckRecordName = UUID().uuidString
                clonedEvent.ckSystemFields = nil
                clonedEvent.day = clonedDay

                // Clone TransitDetails if one is attached to this event.
                if let td = event.transitDetails {
                    let clonedTD = TransitDetails(context: context)
                    context.assign(clonedTD, to: sharedStore)
                    copyTransitDetailsAttributes(from: td, to: clonedTD)
                    clonedTD.ckRecordName = UUID().uuidString
                    clonedTD.ckSystemFields = nil
                    clonedTD.event = clonedEvent
                }
            }
        }

        // Clone flat direct-Trip children.
        for doc in trip.documentsArray {
            let c = TripDocument(context: context)
            context.assign(c, to: sharedStore)
            copyAllSyncableAttributes(from: doc, to: c)
            c.ckRecordName = UUID().uuidString
            c.ckSystemFields = nil
            c.trip = clonedTrip
        }
        for exp in trip.expensesArray {
            let c = TripExpense(context: context)
            context.assign(c, to: sharedStore)
            copyAllSyncableAttributes(from: exp, to: c)
            c.ckRecordName = UUID().uuidString
            c.ckSystemFields = nil
            c.trip = clonedTrip
        }
        for lodge in trip.lodgingArray {
            let c = LodgingInfo(context: context)
            context.assign(c, to: sharedStore)
            copyAllSyncableAttributes(from: lodge, to: c)
            c.ckRecordName = UUID().uuidString
            c.ckSystemFields = nil
            c.trip = clonedTrip
        }
        for member in trip.membersArray {
            let c = TripMember(context: context)
            context.assign(c, to: sharedStore)
            copyAllSyncableAttributes(from: member, to: c)
            c.ckRecordName = UUID().uuidString
            c.ckSystemFields = nil
            c.trip = clonedTrip
        }
        for task in trip.preTripTasksArray {
            let c = PreTripTask(context: context)
            context.assign(c, to: sharedStore)
            copyAllSyncableAttributes(from: task, to: c)
            c.ckRecordName = UUID().uuidString
            c.ckSystemFields = nil
            c.trip = clonedTrip
        }

        // Suppress the push observer: cloned objects have ckSystemFields = nil, so the
        // observer would push them with fresh UUIDs — racing with uploadClone's direct
        // CKModifyRecordsOperation and producing duplicate CloudKit records.
        try SharedSyncEngine.performSuppressingPush { try context.save() }
        daythreadLog.log("TripStoreMigrator: cloned trip '\(trip.name, privacy: .public)' → shared store")
        return clonedTrip
    }

    // MARK: — Attribute copiers

    private static let skipped: Set<String> = [
        "ckRecordName", "ckSystemFields", "migrationState",
        "ekEventIdentifier", "hasReminder", "showInCalendar"
    ]

    /// Copies all attributes NOT in the skipped set from `source` to `dest`.
    /// Uses KVC so that new attributes added to the model are automatically
    /// included without updating this method.
    private func copyAllSyncableAttributes(from source: NSManagedObject, to dest: NSManagedObject) {
        for (key, _) in source.entity.attributesByName {
            guard !Self.skipped.contains(key) else { continue }
            dest.setValue(source.value(forKey: key), forKey: key)
        }
    }

    private func copyTripAttributes(from source: Trip, to dest: Trip) {
        dest.id = source.id
        dest.name = source.name
        dest.destination = source.destination
        dest.startDate = source.startDate
        dest.endDate = source.endDate
        dest.createdAt = source.createdAt
        dest.isArchived = source.isArchived
        dest.gradientSeed = source.gradientSeed
        dest.coverImageData = source.coverImageData
        dest.cloudKitShareID = source.cloudKitShareID
        // migrationState is set by the caller after this returns.
    }

    private func copyDayAttributes(from source: TripDay, to dest: TripDay) {
        dest.id = source.id
        dest.date = source.date
        dest.notes = source.notes
        dest.sortOrder = source.sortOrder
    }

    private func copyEventAttributes(from source: TripEvent, to dest: TripEvent) {
        // Copy all syncable attributes generically so new attributes added to the
        // model are automatically included without updating this method.
        for (key, _) in source.entity.attributesByName {
            guard !Self.skipped.contains(key) else { continue }
            dest.setValue(source.value(forKey: key), forKey: key)
        }
        // Carry over device-local fields: the shared-store clone needs ekEventIdentifier
        // so CalendarService can find and update the existing EKEvent after the NSPCKC
        // original is purged. Without this, the EKEvent is orphaned and the next sync
        // call creates a duplicate. showInCalendar/hasReminder preserve the owner's
        // calendar and reminder preferences through the migration.
        dest.ekEventIdentifier = source.ekEventIdentifier
        dest.showInCalendar    = source.showInCalendar
        dest.hasReminder       = source.hasReminder
    }

    private func copyTransitDetailsAttributes(from source: TransitDetails, to dest: TransitDetails) {
        dest.id = source.id
        dest.carrier = source.carrier
        dest.flightOrTrainNumber = source.flightOrTrainNumber
        dest.pnr = source.pnr
        dest.departureCode = source.departureCode
        dest.arrivalCode = source.arrivalCode
        dest.departureName = source.departureName
        dest.arrivalName = source.arrivalName
        dest.departureTerminal = source.departureTerminal
        dest.arrivalTerminal = source.arrivalTerminal
        dest.departureGate = source.departureGate
        dest.arrivalGate = source.arrivalGate
        dest.seatNumber = source.seatNumber
        dest.baggageClaim = source.baggageClaim
        dest.departureTZIdentifier = source.departureTZIdentifier
        dest.arrivalTZIdentifier = source.arrivalTZIdentifier
        // ckRecordName, ckSystemFields, and event are set by the caller.
    }

    // MARK: — Phase 2 + 3: Upload + Purge

    /// Full migration: clone → upload to custom zone → purge NSPCKC originals.
    /// Returns (clone, share) where share is the live CKShare from makeZoneShare.
    /// On a resumed migration (.uploaded), share is nil — caller should fetch it.
    /// Throws on any CloudKit failure — the clone remains in the shared store
    /// with state .cloned or .uploaded so `resumeInterruptedMigrations()` can retry.
    func migrate(_ trip: Trip, title: String) async throws -> (Trip, CKShare?) {
        let context = PersistenceController.shared.viewContext
        guard let tripID = trip.id else { throw MigrationError.missingTripID }

        // Phase 1: Clone (if not already done from a previous interrupted run).
        let clone: Trip
        if let existing = findExistingClone(of: trip, in: context) {
            daythreadLog.log("TripStoreMigrator: resuming migration for '\(trip.name, privacy: .public)' from state \(existing.migrationState, privacy: .public)")
            clone = existing
        } else {
            clone = try cloneGraph(trip)
        }

        // Phase 2: Create zone + share, push the clone.
        var freshShare: CKShare? = nil
        if clone.migration == .cloned {
            let sharing = SharedZoneSharing()
            let share = try await sharing.makeZoneShare(forTripID: tripID, title: title)
            // Cache the share in SyncState immediately so existingShare() works
            // synchronously on the next call without waiting for a pull-loop fetch.
            cacheShare(share, forTripID: tripID, context: context)
            // Push the entire cloned graph to the new custom zone.
            try await uploadClone(clone, tripID: tripID, context: context)
            // Mark uploaded BEFORE purging — crash here leaves state .uploaded
            // which resumeInterruptedMigrations will finish.
            clone.migration = .uploaded
            clone.cloudKitShareID = share.recordID.recordName
            try SharedSyncEngine.performSuppressingPush { try context.save() }
            freshShare = share
        }

        // Phase 3: Purge the NSPCKC originals (ONLY after confirmed upload).
        if clone.migration == .uploaded {
            try purgeNSPCKCOriginals(of: trip, context: context)
            clone.migration = .done
            try SharedSyncEngine.performSuppressingPush { try context.save() }
            daythreadLog.log("TripStoreMigrator: migration complete for '\(clone.name, privacy: .public)'")
        }

        return (clone, freshShare)
    }

    /// Pushes all shared-store objects in the cloned graph directly via
    /// CKModifyRecordsOperation to the private DB zone.
    /// Does NOT use SharedSyncEngine.pushLocalChanges (which would fire the
    /// echo-suppression path). Calls CKRecordMapper directly and awaits .success.
    private func uploadClone(_ clone: Trip, tripID: UUID, context: NSManagedObjectContext) async throws {
        // Collect all objects in the clone's graph (shared store only).
        var objects: [NSManagedObject] = [clone]
        objects += clone.daysArray as [NSManagedObject]
        for day in clone.daysArray {
            objects += day.eventsArray as [NSManagedObject]
            for event in day.eventsArray {
                if let td = event.transitDetails { objects.append(td) }
            }
        }
        objects += clone.documentsArray as [NSManagedObject]
        objects += clone.expensesArray as [NSManagedObject]
        objects += clone.lodgingArray as [NSManagedObject]
        objects += clone.membersArray as [NSManagedObject]
        objects += clone.preTripTasksArray as [NSManagedObject]

        // Sort parents before children so relationship recordNames are set first.
        let ordered = objects.sorted { TripStoreMigrator.hierarchyRank($0) < TripStoreMigrator.hierarchyRank($1) }

        // Build CKRecords. Since these are brand-new clones with no system fields
        // yet, we set the zoneID explicitly by constructing each record directly.
        let zoneID = SharedZoneSharing.zoneID(for: tripID)
        let container = CKContainer(identifier: "iCloud.com.delonsampaio.daythread.shared")
        let privateDB = container.privateCloudDatabase

        var records: [CKRecord] = []
        for object in ordered {
            guard let entityName = object.entity.name,
                  CKRecordMapper.syncedEntities.contains(entityName) else { continue }
            let recordName = (object.value(forKey: "ckRecordName") as? String) ?? UUID().uuidString
            object.setValue(recordName, forKey: "ckRecordName")
            let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
            let record = CKRecord(recordType: "CD_\(entityName)", recordID: recordID)
            CKRecordMapper.applyFields(of: object, to: record)
            records.append(record)
            // Store system fields back so future updates use the right change tag.
            object.setValue(CKRecordMapper.encodedSystemFields(of: record), forKey: "ckSystemFields")
        }

        guard !records.isEmpty else { return }

        daythreadLog.log("TripStoreMigrator: uploading \(records.count, privacy: .public) records to \(zoneID.zoneName, privacy: .public)")

        // Upload — await confirmed success before proceeding.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            op.savePolicy = .allKeys   // new records — no change tag conflict possible
            op.isAtomic = false        // upload whatever succeeds; partial success is better than none
            op.qualityOfService = .userInitiated
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let error): cont.resume(throwing: error)
                }
            }
            privateDB.add(op)
        }
        daythreadLog.log("TripStoreMigrator: upload confirmed")
        // Suppress: ckSystemFields were set by uploadClone directly — no push needed.
        try SharedSyncEngine.performSuppressingPush { try context.save() }
    }

    /// Deletes the original Trip graph from the NSPCKC store.
    /// ONLY called after uploadClone returns successfully.
    /// SAFETY: only deletes objects whose store is NOT shared.sqlite.
    private func purgeNSPCKCOriginals(of trip: Trip, context: NSManagedObjectContext) throws {
        // Verify this trip is still in the NSPCKC store (not the shared store).
        guard trip.objectID.persistentStore?.url?.lastPathComponent != "shared.sqlite" else {
            daythreadLog.log("TripStoreMigrator: original already in shared store — skip purge")
            return
        }
        daythreadLog.log("TripStoreMigrator: purging NSPCKC original '\(trip.name, privacy: .public)'")
        // Cascade deletes handle all children (days → events → transitDetails,
        // documents, expenses, lodging, members, preTripTasks).
        // Suppress the push observer: these objects are in the NSPCKC private store
        // (not shared.sqlite) so isSharedSynced filters them anyway, but suppressing
        // is defensive and prevents any shared-store objects from being dragged along
        // if they happen to be dirty in viewContext at this moment.
        context.delete(trip)
        try SharedSyncEngine.performSuppressingPush { try context.save() }
        daythreadLog.log("TripStoreMigrator: NSPCKC original purged")
    }

    // MARK: — Interrupted-migration recovery

    /// Find a clone of `trip` already in the shared store (from a previous interrupted run).
    private func findExistingClone(of trip: Trip, in context: NSManagedObjectContext) -> Trip? {
        guard let tripID = trip.id else { return nil }
        let request = Trip.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND migrationState > 0", tripID as CVarArg)
        request.fetchLimit = 1
        guard let store = sharedStore(in: context) else { return nil }
        request.affectedStores = [store]
        return (try? context.fetch(request))?.first
    }

    /// Call on launch to resume any migration interrupted by a crash.
    func resumeInterruptedMigrations() async {
        let context = PersistenceController.shared.viewContext
        guard let store = sharedStore(in: context) else { return }

        let request = Trip.fetchRequest()
        request.predicate = NSPredicate(format: "migrationState > 0 AND migrationState < 3")
        request.affectedStores = [store]
        guard let interrupted = try? context.fetch(request), !interrupted.isEmpty else { return }

        for clone in interrupted {
            daythreadLog.log("TripStoreMigrator: resuming interrupted migration state=\(clone.migrationState, privacy: .public)")
            // Find the NSPCKC original by trip ID to pass to migrate().
            guard let tripID = clone.id else { continue }
            let originalRequest = Trip.fetchRequest()
            originalRequest.predicate = NSPredicate(format: "id == %@ AND migrationState == 0", tripID as CVarArg)
            originalRequest.fetchLimit = 1
            // Search only non-shared stores.
            let privateStores = context.persistentStoreCoordinator?.persistentStores
                .filter { $0.url?.lastPathComponent != "shared.sqlite" } ?? []
            originalRequest.affectedStores = privateStores

            if let original = (try? context.fetch(originalRequest))?.first {
                // Original still exists — resume from current clone state.
                _ = try? await migrate(original, title: clone.name).0
            } else if clone.migration == .uploaded {
                // Original was purged but state not updated — finish.
                clone.migration = .done
                SharedSyncEngine.performSuppressingPush { try? context.save() }
            }
        }
    }

    // MARK: — Helpers

    /// Writes `share`'s system fields into the SyncState row for this trip's zone so
    /// `CloudKitTripSharingBackend.cachedShare(forTripID:)` returns it immediately after
    /// migration — without waiting for the 20s pull-loop to run `fetchZone`.
    private func cacheShare(_ share: CKShare, forTripID tripID: UUID, context: NSManagedObjectContext) {
        guard let store = sharedStore(in: context) else { return }
        let zoneName = SharedZoneSharing.zoneID(for: tripID).zoneName
        let request = SyncState.fetchRequest()
        request.predicate = NSPredicate(format: "zoneName == %@ AND databaseScope == %@", zoneName, "private")
        request.fetchLimit = 1
        let state = (try? context.fetch(request))?.first ?? SyncState(context: context)
        if state.objectID.isTemporaryID { context.assign(state, to: store) }
        state.zoneName = zoneName
        state.ownerName = share.recordID.zoneID.ownerName
        state.databaseScope = "private"
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        share.encodeSystemFields(with: coder)
        state.shareSystemFields = coder.encodedData
        try? context.save()
        daythreadLog.log("TripStoreMigrator: cached CKShare for \(zoneName, privacy: .public)")
    }

    private func sharedStore(in context: NSManagedObjectContext) -> NSPersistentStore? {
        context.persistentStoreCoordinator?.persistentStores
            .first { $0.url?.lastPathComponent == "shared.sqlite" }
    }

    private static func hierarchyRank(_ object: NSManagedObject) -> Int {
        switch object.entity.name {
        case "Trip": return 0
        case "TripDay": return 1
        case "TripEvent": return 2
        case "TransitDetails": return 3
        default: return 1
        }
    }

    enum MigrationError: Error {
        case sharedStoreNotFound
        case missingTripID
    }
}
