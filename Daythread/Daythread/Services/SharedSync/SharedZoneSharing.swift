//
//  SharedZoneSharing.swift
//  Daythread
//
//  Manual CloudKit zone + zone-wide CKShare management for the owner's shared trips.
//  Replaces NSPersistentCloudKitContainer.share() — which defers its export to a
//  BGTaskScheduler activity that returns notPermitted without the 'processing'
//  background mode, causing co-editing updates to arrive only after device lock.
//

import CloudKit
import os

/// Creates and manages per-trip custom CKRecordZones and zone-wide CKShares
/// in the owner's private CloudKit database.
///
/// Zone naming: "Zone-<tripUUID>" — deterministic and unique per trip.
/// Share model: zone-wide (CKShare(recordZoneID:)) so every record saved to the
/// zone is automatically shared as a unit; no per-record parent wiring needed.
struct SharedZoneSharing {
    private let container: CKContainer
    private var privateDB: CKDatabase { container.privateCloudDatabase }

    init(containerIdentifier: String = "iCloud.com.delonsampaio.daythread") {
        self.container = CKContainer(identifier: containerIdentifier)
    }

    // MARK: — Zone ID

    static func zoneID(for tripID: UUID) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "Zone-\(tripID.uuidString)", ownerName: CKCurrentUserDefaultName)
    }

    // MARK: — Create zone + share

    /// Creates the custom zone in the owner's private DB, then creates a zone-wide
    /// CKShare for it. Returns the saved CKShare ready to hand to UICloudSharingController.
    func makeZoneShare(forTripID tripID: UUID, title: String) async throws -> CKShare {
        let zoneID = Self.zoneID(for: tripID)

        // Step 1 — save the zone.
        let zone = CKRecordZone(zoneID: zoneID)
        daythreadLog.log("SharedZoneSharing: creating zone \(zoneID.zoneName, privacy: .public)")
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
            op.qualityOfService = .userInitiated
            op.modifyRecordZonesResultBlock = { result in
                cont.resume(with: result)
            }
            privateDB.add(op)
        }
        daythreadLog.log("SharedZoneSharing: zone created")

        // Step 2 — create and save the zone-wide share.
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        share.publicPermission = .none

        daythreadLog.log("SharedZoneSharing: saving zone-wide CKShare")
        let savedShare: CKShare = try await withCheckedThrowingContinuation { cont in
            let op = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
            op.savePolicy = .ifServerRecordUnchanged
            op.isAtomic = true
            op.perRecordSaveBlock = { _, result in
                // Not used — modifyRecordsResultBlock gives us the outcome.
                _ = result
            }
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    cont.resume(returning: share)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
            privateDB.add(op)
        }
        daythreadLog.log("SharedZoneSharing: CKShare saved — recordName \(savedShare.recordID.recordName, privacy: .public)")
        return savedShare
    }

    // MARK: — Delete zone (stop sharing)

    /// Deletes the custom zone from the private DB. This also deletes all records
    /// in it and notifies participants via zoneNotFound on their next fetch.
    func deleteZone(forTripID tripID: UUID) async throws {
        let zoneID = Self.zoneID(for: tripID)
        daythreadLog.log("SharedZoneSharing: deleting zone \(zoneID.zoneName, privacy: .public)")
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordZonesOperation(recordZonesToSave: nil, recordZoneIDsToDelete: [zoneID])
            op.qualityOfService = .userInitiated
            op.modifyRecordZonesResultBlock = { result in
                cont.resume(with: result)
            }
            privateDB.add(op)
        }
        daythreadLog.log("SharedZoneSharing: zone deleted")
    }

    // MARK: — Fetch existing share (for the management UI)

    /// Fetches the zone-wide CKShare from the private DB. Used when presenting
    /// UICloudSharingController for an already-shared trip.
    /// Retries up to `attempts` times with a short delay — the zone-wide share
    /// record may not be immediately readable right after zone creation.
    func fetchShare(forTripID tripID: UUID, attempts: Int = 1) async throws -> CKShare? {
        let zoneID = Self.zoneID(for: tripID)
        let shareRecordID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        for attempt in 0..<max(1, attempts) {
            do {
                let results = try await privateDB.records(for: [shareRecordID])
                if case .success(let record) = results[shareRecordID], let share = record as? CKShare {
                    return share
                }
            } catch let error as CKError where error.code == .unknownItem {
                // Zone exists but share record not yet visible — retry below.
                daythreadLog.log("SharedZoneSharing: fetchShare unknownItem (attempt \(attempt + 1, privacy: .public)/\(attempts, privacy: .public))")
            }
            if attempt < attempts - 1 {
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
        return nil
    }
}
