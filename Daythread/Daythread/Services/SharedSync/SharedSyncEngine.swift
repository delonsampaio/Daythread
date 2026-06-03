import CloudKit
import CoreData
import os

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

    private init() {}

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

    // MARK: — Per-zone fetch + map

    private func fetchZone(_ zoneID: CKRecordZone.ID) async {
        let context = PersistenceController.shared.viewContext
        guard let sharedStore = Self.sharedStore(in: context) else { return }
        let token = loadToken(zoneName: zoneID.zoneName, context: context)
        do {
            let changes = try await sharedDB.recordZoneChanges(inZoneWith: zoneID, since: token)
            let records = changes.modificationResultsByID.values.compactMap { try? $0.get().record }
            let deletions = changes.deletions.map(\.recordID)
            guard !records.isEmpty || !deletions.isEmpty else { return }

            CKRecordMapper.apply(modifications: records, deletions: deletions, into: context, sharedStore: sharedStore)
            saveToken(changes.changeToken, zoneName: zoneID.zoneName, ownerName: zoneID.ownerName, context: context)
            NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
            daythreadLog.log("SharedSync: zone '\(zoneID.zoneName, privacy: .public)' merged \(records.count, privacy: .public) record(s), \(deletions.count, privacy: .public) deletion(s)")
        } catch {
            daythreadLog.error("SharedSync zone '\(zoneID.zoneName, privacy: .public)' fetch failed: \(error.localizedDescription, privacy: .public)")
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
