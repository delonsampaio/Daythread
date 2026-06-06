import CloudKit
import CoreData
import os

/// Echo-suppression flag. True while the engine applies remote changes or writes back
/// push results, so the SYNCHRONOUS local-save observer doesn't re-push them. Only
/// touched on the main thread; file-scope so the @Sendable observer block can read it.
nonisolated(unsafe) private var sharedSyncApplyingRemote = false

/// Custom sync engine for the SHARED CloudKit database (Path A). Replaces
/// NSPersistentCloudKitContainer's deferred shared-store mirroring with direct
/// CloudKit fetches that run immediately on push, giving participants reliable
/// real-time sync.
///
/// Active only when `PersistenceController.useCustomSharedSync` is true (the shared
/// store is then severed from NSPCKC). While the flag is off, fetches run in
/// read-only diagnostic mode and never touch Core Data, so there is no dual-write
/// with NSPCKC.
@MainActor
final class SharedSyncEngine {
    static let shared = SharedSyncEngine()

    private let container = CKContainer(identifier: "iCloud.com.delonsampaio.daythread")
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var isSyncingShared = false
    private var pendingFetchShared = false
    private var isSyncingPrivate = false
    private var pendingFetchPrivate = false
    private var pollTask: Task<Void, Never>?

    private init() {}

    // MARK: — Foreground polling (resilience against silent-push throttling)

    /// iOS throttles silent pushes, so live sync "eventually stops" if we rely on
    /// push alone. While the app is foregrounded, poll every 20s so co-editor changes
    /// appear within that window even when no push arrives (and instantly when one does).
    func startPeriodicSync() {
        guard PersistenceController.useCustomSharedSync, pollTask == nil else { return }
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { break }
                daythreadLog.log("SharedSync poll tick")
                await fetchAllSharedZones()
                await fetchAllOwnedZones()
            }
        }
    }

    func stopPeriodicSync() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Observes local viewContext saves SYNCHRONOUSLY (queue: nil) and pushes participant
    /// edits. Synchronous delivery is REQUIRED: the observer must run during the save while
    /// `sharedSyncApplyingRemote` is still set, so pulled records aren't re-pushed. (Async
    /// delivery fires after the flag resets → infinite echo loop.) The block extracts only
    /// Sendable values (objectIDs, recordIDs) and hops to the main actor to push.
    func start() {
        guard PersistenceController.useCustomSharedSync else { return }
        let viewContext = PersistenceController.shared.viewContext
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave, object: viewContext, queue: nil
        ) { note in
            guard !sharedSyncApplyingRemote else { return }   // synchronous echo suppression
            let inserted = (note.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? []
            let updated  = (note.userInfo?[NSUpdatedObjectsKey]  as? Set<NSManagedObject>) ?? []
            let deleted  = (note.userInfo?[NSDeletedObjectsKey]  as? Set<NSManagedObject>) ?? []
            let saveIDs = inserted.union(updated).filter(SharedSyncEngine.isSharedSynced).map(\.objectID)
            let deleteIDs = deleted.filter(SharedSyncEngine.isSharedSynced).compactMap(SharedSyncEngine.recordID(forDeleted:))
            guard !saveIDs.isEmpty || !deleteIDs.isEmpty else { return }
            Task { @MainActor in
                await SharedSyncEngine.shared.pushLocalChanges(saveObjectIDs: saveIDs, toDelete: deleteIDs)
            }
        }
    }

    /// Run a Core Data mutation with the push observer suppressed.
    private func suppressingPush(_ body: () -> Void) {
        sharedSyncApplyingRemote = true
        body()
        sharedSyncApplyingRemote = false
    }

    // MARK: — Public entry point

    /// Pull all shared-zone changes into shared.sqlite (or log-only when the flag is off).
    /// Safe to call on launch, foreground, and remote-change push.
    func fetchAllSharedZones() async {
        guard PersistenceController.useCustomSharedSync else {
            await runDiagnosticFetch()   // flag off: read-only, no Core Data writes
            return
        }
        // A fetch is already running — flag that another pass is needed and let the
        // in-flight loop pick it up. This is what keeps mid-sync pushes from being lost.
        guard !isSyncingShared else {
            pendingFetchShared = true
            daythreadLog.log("SharedSync: fetch requested while syncing — queued for re-run")
            return
        }
        isSyncingShared = true
        defer { isSyncingShared = false }

        // Loop until no fetch was requested mid-pass. Per-zone change tokens make extra
        // passes cheap (they fetch only genuinely new records), so this never busy-loops.
        repeat {
            pendingFetchShared = false
            do {
                let dbChanges = try await sharedDB.databaseChanges(since: loadDatabaseToken(scope: "shared"))
                saveDatabaseToken(dbChanges.changeToken, scope: "shared")
                for deletion in dbChanges.deletions {
                    purgeZone(deletion.zoneID)
                }
                var zoneIDs = dbChanges.modifications.map(\.zoneID)
                var anyChanges = false

                // Full zone enumeration fallback: after CKAcceptSharesOperation the new
                // zone can take up to ~60s to appear in databaseChanges due to CloudKit
                // server propagation, and the saved token advances past it in the meantime.
                // Enumerating all zones and fetching any Zone-* zones not yet seen by the
                // change-token path catches newly joined zones within one poll tick.
                // The enumeration is one lightweight request; per-zone record fetches use
                // their own tokens so already-current zones add no extra round trips.
                if let allIDs = try? await fetchAllSharedZoneIDs() {
                    let knownNames = Set(zoneIDs.map(\.zoneName))
                    // Only zones that: (a) use our Zone-* prefix, (b) weren't returned by
                    // databaseChanges, AND (c) have no saved per-zone token (truly new).
                    // Zones with an existing token were already fetched before and would
                    // return 0 records — including them here wastes one API call per zone
                    // per poll tick.
                    let newIDs = allIDs.filter {
                        $0.zoneName.hasPrefix("Zone-") &&
                        !knownNames.contains($0.zoneName) &&
                        loadToken(zoneName: $0.zoneName, databaseScope: "shared") == nil
                    }
                    if !newIDs.isEmpty {
                        daythreadLog.log("SharedSync: zone enumeration found \(newIDs.count, privacy: .public) new shared zone(s) not in change token")
                        zoneIDs.append(contentsOf: newIDs)
                    }
                }

                for zoneID in zoneIDs {
                    let n = await fetchZone(zoneID, in: sharedDB, databaseScope: "shared")
                    if n > 0 { anyChanges = true }
                }
                // Post once after all zones — avoids N×sections synchronous reload()
                // calls on the main thread when multiple zones change in one pass.
                if anyChanges {
                    NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
                }
            } catch {
                daythreadLog.error("SharedSync fetchAll failed: \(error.localizedDescription, privacy: .public)")
            }
        } while pendingFetchShared
    }

    /// Returns all zone IDs currently visible in the shared database.
    /// Uses CKFetchRecordZonesOperation (lightweight — zone metadata only, no records).
    private func fetchAllSharedZoneIDs() async throws -> [CKRecordZone.ID] {
        try await withCheckedThrowingContinuation { continuation in
            var zoneIDs: [CKRecordZone.ID] = []
            let op = CKFetchRecordZonesOperation.fetchAllRecordZonesOperation()
            op.perRecordZoneResultBlock = { zoneID, result in
                if case .success = result { zoneIDs.append(zoneID) }
            }
            op.fetchRecordZonesResultBlock = { result in
                switch result {
                case .success: continuation.resume(returning: zoneIDs)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            sharedDB.add(op)
        }
    }

    /// Pull changes for all custom zones the owner created in their private DB.
    /// Skips NSPCKC's built-in zone (com.apple.coredata.cloudkit.zone) — we only
    /// care about the custom "Zone-<tripUUID>" zones created by the sharing engine.
    func fetchAllOwnedZones() async {
        guard PersistenceController.useCustomSharedSync else { return }
        guard !isSyncingPrivate else {
            pendingFetchPrivate = true
            daythreadLog.log("SharedSync: owned-zone fetch queued (already syncing)")
            return
        }
        isSyncingPrivate = true
        defer { isSyncingPrivate = false }

        repeat {
            pendingFetchPrivate = false
            do {
                let dbChanges = try await privateDB.databaseChanges(since: loadDatabaseToken(scope: "private"))
                saveDatabaseToken(dbChanges.changeToken, scope: "private")
                for deletion in dbChanges.deletions where deletion.zoneID.zoneName.hasPrefix("Zone-") {
                    purgeZone(deletion.zoneID)
                }
                let zoneIDs = dbChanges.modifications.map(\.zoneID)
                    .filter { $0.zoneName.hasPrefix("Zone-") }  // only our custom zones
                var anyChanges = false
                for zoneID in zoneIDs {
                    let n = await fetchZone(zoneID, in: privateDB, databaseScope: "private")
                    if n > 0 { anyChanges = true }
                }
                if anyChanges {
                    NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
                }
            } catch {
                daythreadLog.error("SharedSync fetchOwnedZones failed: \(error.localizedDescription, privacy: .public)")
            }
        } while pendingFetchPrivate
    }

    /// Fetch a specific just-joined zone, retrying briefly: immediately after
    /// CKAcceptSharesOperation completes the zone is often not yet queryable.
    func fetchJoinedZone(_ zoneID: CKRecordZone.ID) async {
        guard PersistenceController.useCustomSharedSync else { return }
        for attempt in 0..<6 {
            let count = await fetchZone(zoneID, in: sharedDB, databaseScope: "shared")
            if count > 0 {
                NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
                return
            }
            daythreadLog.log("SharedSync: joined zone empty (attempt \(attempt, privacy: .public)), retrying")
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    // MARK: — Per-zone fetch + map

    @discardableResult
    private func fetchZone(_ zoneID: CKRecordZone.ID, in db: CKDatabase, databaseScope: String) async -> Int {
        let context = PersistenceController.shared.viewContext
        guard let sharedStore = Self.sharedStore(in: context) else { return 0 }
        let token = loadToken(zoneName: zoneID.zoneName, databaseScope: databaseScope)
        do {
            let changes = try await db.recordZoneChanges(inZoneWith: zoneID, since: token)
            let allRecords = changes.modificationResultsByID.values.compactMap { try? $0.get().record }
            // Separate the CKShare (system record, not a CD_ entity) from data records.
            let share = allRecords.first(where: { $0.recordType == CKRecord.SystemType.share }) as? CKShare
            let records = allRecords.filter { $0.recordType != CKRecord.SystemType.share }
            let deletions = changes.deletions.map(\.recordID)
            guard !records.isEmpty || !deletions.isEmpty || share != nil else { return 0 }

            // CKRecordMapper.apply is the expensive part: it iterates and inserts/updates
            // potentially hundreds of records. Run it on a background context so the main
            // thread is never blocked. Token + dedup are lightweight (single-row fetch) and
            // stay on viewContext where @MainActor-isolated NSManagedObject APIs are safe.
            let bgContext = PersistenceController.shared.container.newBackgroundContext()
            bgContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
            await bgContext.perform {
                guard let bgStore = Self.sharedStore(in: bgContext) else { return }
                // Push observer only watches viewContext — no suppressingPush needed here.
                CKRecordMapper.apply(modifications: records, deletions: deletions, into: bgContext, sharedStore: bgStore, autoSave: true)
            }

            // Lightweight main-thread work: persist the change token and collapse any
            // duplicate TripMember rows that arrived before each device's record synced.
            saveToken(changes.changeToken, zoneName: zoneID.zoneName, ownerName: zoneID.ownerName, databaseScope: databaseScope, share: share)
            deduplicateMembersForZone(zoneID.zoneName, in: context, sharedStore: sharedStore)
            if context.hasChanges { suppressingPush { try? context.save() } }
            // Notification is posted by the caller (fetchAllSharedZones/fetchAllOwnedZones/
            // fetchJoinedZone) once after ALL zones finish, not once per zone, to avoid
            // N×sections synchronous reload() calls on the main thread per poll tick.
            daythreadLog.log("SharedSync: zone '\(zoneID.zoneName, privacy: .public)' merged \(records.count, privacy: .public) record(s), \(deletions.count, privacy: .public) deletion(s)")
            return records.count + deletions.count
        } catch let error as CKError where error.code == .zoneNotFound {
            daythreadLog.log("SharedSync: zone '\(zoneID.zoneName, privacy: .public)' deleted — purging local data")
            purgeZone(zoneID)
            return 0
        } catch {
            daythreadLog.error("SharedSync zone '\(zoneID.zoneName, privacy: .public)' fetch failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    /// Deduplicates TripMember records for the trip whose zone matches `zoneName`.
    /// Two devices can independently register the same participant before the other's
    /// record syncs in — this collapses duplicates by appleUserID, keeping the
    /// highest-privilege record, so the roster never shows the same person twice.
    private func deduplicateMembersForZone(_ zoneName: String, in context: NSManagedObjectContext, sharedStore: NSPersistentStore) {
        let uuidStr = zoneName.hasPrefix("Zone-") ? String(zoneName.dropFirst(5)) : nil
        guard let uuidStr, let tripID = UUID(uuidString: uuidStr) else { return }
        let request = Trip.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", tripID as CVarArg)
        request.affectedStores = [sharedStore]
        request.fetchLimit = 1
        guard let trip = (try? context.fetch(request))?.first else { return }

        let memberRequest = TripMember.fetchRequest()
        memberRequest.predicate = NSPredicate(format: "trip == %@ AND appleUserID != ''", trip)
        guard let members = try? context.fetch(memberRequest), members.count > 1 else { return }

        var seen: [String: TripMember] = [:]
        for m in members {
            let uid = m.appleUserID
            if let existing = seen[uid] {
                let keepNew = m.role.privilege > existing.role.privilege
                    || (m.role == existing.role && m.joinedAt < existing.joinedAt)
                suppressingPush { context.delete(keepNew ? existing : m) }
                if keepNew { seen[uid] = m }
            } else {
                seen[uid] = m
            }
        }
        // Caller saves — see fetchZone's single batched save.
    }

    // MARK: — Zone purge

    /// Purges all shared-store objects belonging to `zoneID` and clears the
    /// zone's SyncState tokens. Called when recordZoneChanges reports the zone
    /// as deleted (owner stopped sharing or participant self-removed).
    ///
    /// OWNER SAFETY: the owner deletes the zone intentionally when stopping sharing.
    /// On their device the zone appears as a deletion in fetchAllOwnedZones, but the
    /// trip should stay — it just becomes unshared again. We detect this by checking
    /// whether the trip's cloudKitShareID matches the zone before deleting: if the
    /// trip has already had its cloudKitShareID cleared by stopSharing(), skip the
    /// delete. If it hasn't (e.g. a forced purge), clear the ID instead of deleting.
    private func purgeZone(_ zoneID: CKRecordZone.ID) {
        let context = PersistenceController.shared.viewContext
        guard let sharedStore = Self.sharedStore(in: context) else { return }

        // Find the Trip in the shared store whose zone matches this zoneID.
        // Zone name is "Zone-<tripUUID>"; trip.id gives us the UUID.
        let zoneName = zoneID.zoneName  // e.g. "Zone-550E8400-..."
        let tripUUIDString = zoneName.hasPrefix("Zone-")
            ? String(zoneName.dropFirst(5))
            : nil

        if let uuidStr = tripUUIDString, let tripID = UUID(uuidString: uuidStr) {
            let request = Trip.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", tripID as CVarArg)
            request.affectedStores = [sharedStore]
            request.fetchLimit = 1
            if let trip = (try? context.fetch(request))?.first {
                // Owner check: if the zone owner matches the current user, this is
                // an owner-initiated stop-sharing — keep the trip, just clear its
                // share metadata so it becomes a normal private trip again.
                let myID = UserDefaults.standard.string(forKey: "daythread.currentUserCloudKitID")
                let isOwnerZone = zoneID.ownerName == CKCurrentUserDefaultName
                    || (myID != nil && zoneID.ownerName == myID)
                if isOwnerZone {
                    // Only clear the share ID if it still points to this zone's share.
                    // stopSharing() already cleared it — avoid double-writes.
                    if trip.cloudKitShareID != nil {
                        trip.cloudKitShareID = nil
                    }
                    daythreadLog.log("SharedSync purgeZone: owner stopped sharing zone \(zoneName, privacy: .public) — trip retained")
                } else {
                    // Participant device: cascade delete removes the whole trip.
                    context.delete(trip)
                    daythreadLog.log("SharedSync purgeZone: deleted trip for zone \(zoneName, privacy: .public)")
                }
            }
        } else {
            // Fallback: delete all synced entities in the shared store that have
            // a ckRecordName matching records from this zone. Since we don't have
            // a direct zone→object index, just log and skip — the user will see
            // the trip disappear on next launch's fresh fetch.
            daythreadLog.log("SharedSync purgeZone: zone \(zoneName, privacy: .public) has no UUID prefix — skipping purge")
        }

        // Remove zone tokens from UserDefaults (tokens are no longer stored in Core Data).
        for scope in ["shared", "private"] {
            UserDefaults.standard.removeObject(forKey: "SharedSync.zoneToken.\(zoneID.zoneName).\(scope)")
            UserDefaults.standard.removeObject(forKey: "SharedSync.zoneOwner.\(zoneID.zoneName).\(scope)")
            UserDefaults.standard.removeObject(forKey: "SharedSync.zoneShare.\(zoneID.zoneName).\(scope)")
        }

        if context.hasChanges {
            // Wrap save in suppressingPush: the deleted objects are being removed
            // because their zone was already deleted server-side, so pushing those
            // deletes back to CloudKit would either fail (zone gone) or corrupt
            // another user's data. Suppress the echo entirely.
            suppressingPush { try? context.save() }
            NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
        }
    }

    // MARK: — Change-token persistence (UserDefaults — no PSC lock, no main-thread Core Data I/O)
    // Zone tokens mirror the database-level token pattern (loadDatabaseToken/saveDatabaseToken).
    // SyncState Core Data entity is no longer written; existing rows are harmless orphans.

    private func loadToken(zoneName: String, databaseScope: String) -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: "SharedSync.zoneToken.\(zoneName).\(databaseScope)") else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveToken(
        _ token: CKServerChangeToken,
        zoneName: String,
        ownerName: String,
        databaseScope: String,
        share: CKShare? = nil
    ) {
        let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        UserDefaults.standard.set(tokenData, forKey: "SharedSync.zoneToken.\(zoneName).\(databaseScope)")
        UserDefaults.standard.set(ownerName, forKey: "SharedSync.zoneOwner.\(zoneName).\(databaseScope)")
        if let share {
            let coder = NSKeyedArchiver(requiringSecureCoding: true)
            share.encodeSystemFields(with: coder)
            UserDefaults.standard.set(coder.encodedData, forKey: "SharedSync.zoneShare.\(zoneName).\(databaseScope)")
        }
    }

    private func loadDatabaseToken(scope: String) -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: "SharedSync.dbToken.\(scope)") else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveDatabaseToken(_ token: CKServerChangeToken, scope: String) {
        let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        UserDefaults.standard.set(data, forKey: "SharedSync.dbToken.\(scope)")
    }

    nonisolated private static func sharedStore(in context: NSManagedObjectContext) -> NSPersistentStore? {
        context.persistentStoreCoordinator?.persistentStores
            .first { $0.url?.lastPathComponent == "shared.sqlite" }
    }

    // MARK: — Push (local participant edits → shared zone)

    /// Records in zones named "Zone-<uuid>" with ownerName == CKCurrentUserDefaultName
    /// live in the owner's private DB. Everything else (participant-joined zones) lives
    /// in the shared DB.
    nonisolated private static func database(
        forZone zoneID: CKRecordZone.ID,
        in container: CKContainer
    ) -> CKDatabase {
        // CKCurrentUserDefaultName ("__defaultOwner__") is the sentinel used when
        // creating zones. After a fetch CloudKit returns the real owner record name
        // in system fields — so we must also accept the cached real ID. Otherwise
        // pushes after the first fetchAllOwnedZones would be routed to the shared DB.
        if zoneID.zoneName.hasPrefix("Zone-") {
            let myID = UserDefaults.standard.string(forKey: "daythread.currentUserCloudKitID")
            if zoneID.ownerName == CKCurrentUserDefaultName || zoneID.ownerName == myID {
                return container.privateCloudDatabase
            }
        }
        return container.sharedCloudDatabase
    }

    fileprivate func pushLocalChanges(saveObjectIDs: [NSManagedObjectID], toDelete recordIDs: [CKRecord.ID]) async {
        let context = PersistenceController.shared.viewContext
        let objects = saveObjectIDs.compactMap { try? context.existingObject(with: $0) }
        // Parents first so newly-created parents get recordNames before children encode.
        let ordered = objects.sorted { Self.hierarchyRank($0) < Self.hierarchyRank($1) }

        var records: [CKRecord] = []
        var objectByName: [String: NSManagedObject] = [:]
        var tempAssetURLs: [URL] = []
        for object in ordered {
            guard let record = CKRecordMapper.ckRecord(for: object) else { continue }
            // Collect CKAsset URLs for cleanup after upload.
            for key in record.allKeys() {
                if let asset = record[key] as? CKAsset, let url = asset.fileURL {
                    tempAssetURLs.append(url)
                }
            }
            records.append(record)
            objectByName[record.recordID.recordName] = object
        }
        guard !records.isEmpty || !recordIDs.isEmpty else { return }

        // Group saves and deletes by their target database.
        var savesByDB: [ObjectIdentifier: (CKDatabase, [CKRecord])] = [:]
        for record in records {
            let db = Self.database(forZone: record.recordID.zoneID, in: container)
            let key = ObjectIdentifier(db)
            if savesByDB[key] == nil { savesByDB[key] = (db, []) }
            savesByDB[key]!.1.append(record)
        }

        var deletesByDB: [ObjectIdentifier: (CKDatabase, [CKRecord.ID])] = [:]
        for recordID in recordIDs {
            let db = Self.database(forZone: recordID.zoneID, in: container)
            let key = ObjectIdentifier(db)
            if deletesByDB[key] == nil { deletesByDB[key] = (db, []) }
            deletesByDB[key]!.1.append(recordID)
        }

        // Collect all database keys involved.
        let allKeys = Set(savesByDB.keys).union(deletesByDB.keys)
        for key in allKeys {
            let db = savesByDB[key]?.0 ?? deletesByDB[key]!.0
            let toSave = savesByDB[key]?.1 ?? []
            let toDelete = deletesByDB[key]?.1 ?? []

            do {
                let (saveResults, _) = try await db.modifyRecords(
                    saving: toSave, deleting: toDelete,
                    savePolicy: .ifServerRecordUnchanged, atomically: false
                )
                var conflicts: [CKRecord] = []
                for (recordID, result) in saveResults {
                    switch result {
                    case .success(let saved):
                        writeBack(saved, to: objectByName[recordID.recordName])
                    case .failure(let error):
                        if let ckError = error as? CKError, ckError.code == .serverRecordChanged,
                           let server = ckError.serverRecord, let object = objectByName[recordID.recordName] {
                            CKRecordMapper.applyFields(of: object, to: server)  // client trumps
                            conflicts.append(server)
                        } else {
                            daythreadLog.error("SharedSync push failed \(recordID.recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        }
                    }
                }
                // Retry merged conflicts once against the now-current server records.
                if !conflicts.isEmpty {
                    let (retry, _) = try await db.modifyRecords(
                        saving: conflicts, deleting: [],
                        savePolicy: .ifServerRecordUnchanged, atomically: false
                    )
                    for (recordID, result) in retry {
                        if case .success(let saved) = result { writeBack(saved, to: objectByName[recordID.recordName]) }
                    }
                }
            } catch {
                daythreadLog.error("SharedSync push op failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        suppressingPush { try? context.save() }
        daythreadLog.log("SharedSync push: \(records.count, privacy: .public) saved, \(recordIDs.count, privacy: .public) deleted")
        // Clean up temp files written by CKRecordMapper.writeTempAsset.
        for url in tempAssetURLs { try? FileManager.default.removeItem(at: url) }
    }

    /// Persist the saved record's identity + change tag back onto the local object.
    private func writeBack(_ record: CKRecord, to object: NSManagedObject?) {
        guard let object else { return }
        object.setValue(record.recordID.recordName, forKey: "ckRecordName")
        object.setValue(CKRecordMapper.encodedSystemFields(of: record), forKey: "ckSystemFields")
    }

    nonisolated private static func isSharedSynced(_ object: NSManagedObject) -> Bool {
        guard let name = object.entity.name, CKRecordMapper.syncedEntities.contains(name) else { return false }
        return object.objectID.persistentStore?.url?.lastPathComponent == "shared.sqlite"
    }

    /// Build the CKRecord.ID for a just-deleted object from its stored system fields.
    nonisolated private static func recordID(forDeleted object: NSManagedObject) -> CKRecord.ID? {
        guard let data = object.value(forKey: "ckSystemFields") as? Data,
              let record = CKRecordMapper.record(fromSystemFields: data) else { return nil }
        return record.recordID
    }

    nonisolated private static func hierarchyRank(_ object: NSManagedObject) -> Int {
        switch object.entity.name {
        case "Trip": return 0
        case "TripEvent": return 2
        case "TransitDetails": return 3
        default: return 1   // TripDay, TripMember, TripExpense, TripDocument, LodgingInfo, PreTripTask
        }
    }

    // MARK: — Diagnostic (flag off): log records without touching Core Data

    func runDiagnosticFetch() async {
        do {
            let dbChanges = try await sharedDB.databaseChanges(since: nil)
            let zoneIDs = dbChanges.modifications.map(\.zoneID)
            daythreadLog.log("SharedSync diag: \(zoneIDs.count, privacy: .public) shared zone(s)")
            for zoneID in zoneIDs {
                let changes = try await sharedDB.recordZoneChanges(inZoneWith: zoneID, since: nil)
                daythreadLog.log("SharedSync diag: zone '\(zoneID.zoneName, privacy: .public)' — \(changes.modificationResultsByID.count, privacy: .public) record(s)")
            }
            daythreadLog.log("SharedSync diag: complete")
        } catch {
            daythreadLog.error("SharedSync diag failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
