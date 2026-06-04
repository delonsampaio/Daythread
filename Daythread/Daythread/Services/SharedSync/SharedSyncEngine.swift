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
    private var isSyncing = false
    /// Set when a push/poll requests a fetch while one is already running. The in-flight
    /// fetch loops once more on completion so bunched-up pushes are never dropped — the
    /// old "SKIPPED — already syncing" early-return silently lost co-editor changes that
    /// arrived mid-sync (only a relaunch's fetch-since-token recovered them).
    private var pendingFetch = false
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
                daythreadLog.log("SharedSync poll tick (isSyncing=\(self.isSyncing, privacy: .public))")
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
        guard !isSyncing else {
            pendingFetch = true
            daythreadLog.log("SharedSync: fetch requested while syncing — queued for re-run")
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        // Loop until no fetch was requested mid-pass. Per-zone change tokens make extra
        // passes cheap (they fetch only genuinely new records), so this never busy-loops.
        repeat {
            pendingFetch = false
            do {
                let dbChanges = try await sharedDB.databaseChanges(since: nil)
                let zoneIDs = dbChanges.modifications.map(\.zoneID)
                for zoneID in zoneIDs {
                    await fetchZone(zoneID, in: sharedDB, databaseScope: "shared")
                }
            } catch {
                daythreadLog.error("SharedSync fetchAll failed: \(error.localizedDescription, privacy: .public)")
            }
        } while pendingFetch
    }

    /// Pull changes for all custom zones the owner created in their private DB.
    /// Skips NSPCKC's built-in zone (com.apple.coredata.cloudkit.zone) — we only
    /// care about the custom "Zone-<tripUUID>" zones created by the sharing engine.
    func fetchAllOwnedZones() async {
        guard PersistenceController.useCustomSharedSync else { return }
        guard !isSyncing else {
            pendingFetch = true
            daythreadLog.log("SharedSync: owned-zone fetch queued (already syncing)")
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        repeat {
            pendingFetch = false
            do {
                let dbChanges = try await privateDB.databaseChanges(since: nil)
                let zoneIDs = dbChanges.modifications.map(\.zoneID)
                    .filter { $0.zoneName.hasPrefix("Zone-") }  // only our custom zones
                for zoneID in zoneIDs {
                    await fetchZone(zoneID, in: privateDB, databaseScope: "private")
                }
            } catch {
                daythreadLog.error("SharedSync fetchOwnedZones failed: \(error.localizedDescription, privacy: .public)")
            }
        } while pendingFetch
    }

    /// Fetch a specific just-joined zone, retrying briefly: immediately after
    /// CKAcceptSharesOperation completes the zone is often not yet queryable.
    func fetchJoinedZone(_ zoneID: CKRecordZone.ID) async {
        guard PersistenceController.useCustomSharedSync else { return }
        for attempt in 0..<6 {
            let count = await fetchZone(zoneID, in: sharedDB, databaseScope: "shared")
            if count > 0 { return }
            daythreadLog.log("SharedSync: joined zone empty (attempt \(attempt, privacy: .public)), retrying")
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    // MARK: — Per-zone fetch + map

    @discardableResult
    private func fetchZone(_ zoneID: CKRecordZone.ID, in db: CKDatabase, databaseScope: String) async -> Int {
        let context = PersistenceController.shared.viewContext
        guard let sharedStore = Self.sharedStore(in: context) else { return 0 }
        let token = loadToken(zoneName: zoneID.zoneName, databaseScope: databaseScope, context: context)
        do {
            let changes = try await db.recordZoneChanges(inZoneWith: zoneID, since: token)
            let allRecords = changes.modificationResultsByID.values.compactMap { try? $0.get().record }
            // Separate the CKShare (system record, not a CD_ entity) from data records.
            let share = allRecords.first(where: { $0.recordType == CKRecord.SystemType.share }) as? CKShare
            let records = allRecords.filter { $0.recordType != CKRecord.SystemType.share }
            let deletions = changes.deletions.map(\.recordID)
            guard !records.isEmpty || !deletions.isEmpty || share != nil else { return 0 }

            suppressingPush {
                CKRecordMapper.apply(modifications: records, deletions: deletions, into: context, sharedStore: sharedStore)
            }
            saveToken(changes.changeToken, zoneName: zoneID.zoneName, ownerName: zoneID.ownerName, databaseScope: databaseScope, context: context, share: share)
            NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
            daythreadLog.log("SharedSync: zone '\(zoneID.zoneName, privacy: .public)' merged \(records.count, privacy: .public) record(s), \(deletions.count, privacy: .public) deletion(s)")
            return records.count
        } catch let error as CKError where error.code == .zoneNotFound {
            daythreadLog.error("SharedSync: zone '\(zoneID.zoneName, privacy: .public)' not found — will purge on next task")
            return 0
        } catch {
            daythreadLog.error("SharedSync zone '\(zoneID.zoneName, privacy: .public)' fetch failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    // MARK: — Change-token persistence (SyncState, local to shared.sqlite)

    private func loadToken(zoneName: String, databaseScope: String, context: NSManagedObjectContext) -> CKServerChangeToken? {
        let request = SyncState.fetchRequest()
        request.predicate = NSPredicate(format: "zoneName == %@ AND databaseScope == %@", zoneName, databaseScope)
        request.fetchLimit = 1
        guard let data = (try? context.fetch(request))?.first?.changeTokenData else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveToken(
        _ token: CKServerChangeToken,
        zoneName: String,
        ownerName: String,
        databaseScope: String,
        context: NSManagedObjectContext,
        share: CKShare? = nil
    ) {
        let request = SyncState.fetchRequest()
        request.predicate = NSPredicate(format: "zoneName == %@ AND databaseScope == %@", zoneName, databaseScope)
        request.fetchLimit = 1
        let state = (try? context.fetch(request))?.first ?? SyncState(context: context)
        if let store = Self.sharedStore(in: context), state.objectID.isTemporaryID {
            context.assign(state, to: store)
        }
        state.zoneName = zoneName
        state.ownerName = ownerName
        state.databaseScope = databaseScope
        state.changeTokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        state.lastSyncedAt = Date()
        if let share {
            let coder = NSKeyedArchiver(requiringSecureCoding: true)
            share.encodeSystemFields(with: coder)
            state.shareSystemFields = coder.encodedData
        }
        try? context.save()
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
        if zoneID.zoneName.hasPrefix("Zone-") && zoneID.ownerName == CKCurrentUserDefaultName {
            return container.privateCloudDatabase
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
        for object in ordered {
            guard let record = CKRecordMapper.ckRecord(for: object) else { continue }
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
