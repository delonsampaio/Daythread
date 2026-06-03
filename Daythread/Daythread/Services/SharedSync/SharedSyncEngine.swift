import CloudKit
import CoreData
import os

/// Custom sync engine for the SHARED CloudKit database (Path A). Replaces
/// NSPersistentCloudKitContainer's deferred shared-store mirroring with direct
/// CloudKit fetches/pushes that run immediately on push, giving participants
/// reliable real-time sync.
///
/// Phase 2 (current): read-only DIAGNOSTIC fetch that logs the real record format
/// (recordName scheme, relationship values) so the mapper can be finalized. It does
/// not touch Core Data and runs regardless of the useCustomSharedSync flag, since it
/// reads CloudKit's shared database directly.
@MainActor
final class SharedSyncEngine {
    static let shared = SharedSyncEngine()

    private let container = CKContainer(identifier: "iCloud.com.delonsampaio.daythread")
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    private init() {}

    /// DIAGNOSTIC: enumerate shared zones and log each record's identity +
    /// relationship fields. Confirms NSPCKC's recordName format and that
    /// CD_day / CD_trip hold recordName strings, before we build the mapper.
    func runDiagnosticFetch() async {
        do {
            let dbChanges = try await sharedDB.databaseChanges(since: nil)
            let zoneIDs = dbChanges.modifications.map(\.zoneID)
            daythreadLog.log("SharedSync diag: \(zoneIDs.count, privacy: .public) shared zone(s)")

            for zoneID in zoneIDs {
                let changes = try await sharedDB.recordZoneChanges(inZoneWith: zoneID, since: nil)
                daythreadLog.log("SharedSync diag: zone '\(zoneID.zoneName, privacy: .public)' owner '\(zoneID.ownerName, privacy: .public)' — \(changes.modificationResultsByID.count, privacy: .public) record(s)")

                for (recordID, result) in changes.modificationResultsByID {
                    guard case .success(let modification) = result else { continue }
                    let record = modification.record
                    let cdId = (record["CD_id"] as? String) ?? "nil"
                    let entity = (record["CD_entityName"] as? String) ?? "?"
                    let day = (record["CD_day"] as? String) ?? "-"
                    let trip = (record["CD_trip"] as? String) ?? "-"
                    daythreadLog.log("SharedSync diag: type=\(record.recordType, privacy: .public) recordName=\(recordID.recordName, privacy: .public) CD_id=\(cdId, privacy: .public) entity=\(entity, privacy: .public) CD_day=\(day, privacy: .public) CD_trip=\(trip, privacy: .public)")
                }
            }
            daythreadLog.log("SharedSync diag: complete")
        } catch {
            daythreadLog.error("SharedSync diag failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
