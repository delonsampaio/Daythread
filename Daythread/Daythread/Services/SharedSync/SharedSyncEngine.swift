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
    private var isSyncing = false
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
                await fetchAllSharedZones()
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
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let dbChanges = try await sharedDB.databaseChanges(since: nil)
            let zoneIDs = dbChanges.modifications.map(\.zoneID)
            for zoneID in zoneIDs {
                await fetchZone(zoneID)
            }
        } catch {
            daythreadLog.error("SharedSync fetchAll failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Fetch a specific just-joined zone, retrying briefly: immediately after
    /// CKAcceptSharesOperation completes the zone is often not yet queryable.
    func fetchJoinedZone(_ zoneID: CKRecordZone.ID) async {
        guard PersistenceController.useCustomSharedSync else { return }
        for attempt in 0..<6 {
            let count = await fetchZone(zoneID)
            if count > 0 { return }
            daythreadLog.log("SharedSync: joined zone empty (attempt \(attempt, privacy: .public)), retrying")
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    // MARK: — Per-zone fetch + map

    @discardableResult
    private func fetchZone(_ zoneID: CKRecordZone.ID) async -> Int {
        let context = PersistenceController.shared.viewContext
        guard let sharedStore = Self.sharedStore(in: context) else { return 0 }
        let token = loadToken(zoneName: zoneID.zoneName, context: context)
        do {
            let changes = try await sharedDB.recordZoneChanges(inZoneWith: zoneID, since: token)
            let records = changes.modificationResultsByID.values.compactMap { try? $0.get().record }
            let deletions = changes.deletions.map(\.recordID)
            guard !records.isEmpty || !deletions.isEmpty else { return 0 }

            suppressingPush {
                CKRecordMapper.apply(modifications: records, deletions: deletions, into: context, sharedStore: sharedStore)
            }
            saveToken(changes.changeToken, zoneName: zoneID.zoneName, ownerName: zoneID.ownerName, context: context)
            NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
            daythreadLog.log("SharedSync: zone '\(zoneID.zoneName, privacy: .public)' merged \(records.count, privacy: .public) record(s), \(deletions.count, privacy: .public) deletion(s)")
            return records.count
        } catch {
            daythreadLog.error("SharedSync zone '\(zoneID.zoneName, privacy: .public)' fetch failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    // MARK: — Change-token persistence (SyncState, local to shared.sqlite)

    private func loadToken(zoneName: String, context: NSManagedObjectContext) -> CKServerChangeToken? {
        let request = SyncState.fetchRequest()
        request.predicate = NSPredicate(format: "zoneName == %@", zoneName)
        request.fetchLimit = 1
        guard let data = (try? context.fetch(request))?.first?.changeTokenData else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveToken(_ token: CKServerChangeToken, zoneName: String, ownerName: String, context: NSManagedObjectContext) {
        let request = SyncState.fetchRequest()
        request.predicate = NSPredicate(format: "zoneName == %@", zoneName)
        request.fetchLimit = 1
        let state = (try? context.fetch(request))?.first ?? SyncState(context: context)
        if let store = Self.sharedStore(in: context), state.objectID.isTemporaryID {
            context.assign(state, to: store)
        }
        state.zoneName = zoneName
        state.ownerName = ownerName
        state.changeTokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        state.lastSyncedAt = Date()
        try? context.save()
    }

    nonisolated private static func sharedStore(in context: NSManagedObjectContext) -> NSPersistentStore? {
        context.persistentStoreCoordinator?.persistentStores
            .first { $0.url?.lastPathComponent == "shared.sqlite" }
    }

    // MARK: — Push (local participant edits → shared zone)

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

        do {
            let (saveResults, _) = try await sharedDB.modifyRecords(
                saving: records, deleting: recordIDs,
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
                let (retry, _) = try await sharedDB.modifyRecords(
                    saving: conflicts, deleting: [],
                    savePolicy: .ifServerRecordUnchanged, atomically: false
                )
                for (recordID, result) in retry {
                    if case .success(let saved) = result { writeBack(saved, to: objectByName[recordID.recordName]) }
                }
            }
            suppressingPush { try? context.save() }
            daythreadLog.log("SharedSync push: \(records.count, privacy: .public) saved, \(recordIDs.count, privacy: .public) deleted")
        } catch {
            daythreadLog.error("SharedSync push op failed: \(error.localizedDescription, privacy: .public)")
        }
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
