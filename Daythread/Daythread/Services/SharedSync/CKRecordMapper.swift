import CloudKit
import CoreData
import os

/// Maps CloudKit shared-zone records (NSPersistentCloudKitContainer's `CD_` format)
/// to/from the local Core Data graph in shared.sqlite. Generic over the model:
/// each attribute `X` maps to CKRecord field `CD_X`; each to-one relationship `R`
/// maps to field `CD_R` holding the related record's recordName (see the format
/// spec). recordName is persisted on each object's `ckRecordName` (≠ `id`).
enum CKRecordMapper {
    /// Entities the engine syncs (the trip graph). Used for delete lookups.
    nonisolated static let syncedEntities = [
        "Trip", "TripDay", "TripEvent", "TransitDetails", "TripMember",
        "TripDocument", "TripExpense", "LodgingInfo", "PreTripTask"
    ]

    /// Device-local / engine-internal attributes that must never be imported or pushed.
    nonisolated private static let skippedAttributes: Set<String> = [
        "ckRecordName", "ckSystemFields", "ekEventIdentifier", "hasReminder", "showInCalendar"
    ]

    // MARK: — Read path (CKRecord → Core Data)

    /// Upserts `modifications` and removes `deletions` in `context`, assigning new
    /// objects to `sharedStore`. Two passes: attributes first (building a
    /// recordName→object map), then to-one relationships. Caller wraps in `perform`.
    nonisolated static func apply(
        modifications: [CKRecord],
        deletions: [CKRecord.ID],
        into context: NSManagedObjectContext,
        sharedStore: NSPersistentStore
    ) {
        let records = modifications.filter { $0.recordType.hasPrefix("CD_") }

        // Pass 1 — upsert objects + attributes; build recordName → object.
        var byRecordName: [String: NSManagedObject] = [:]
        for record in records {
            let entityName = String(record.recordType.dropFirst(3)) // strip "CD_"
            guard syncedEntities.contains(entityName) else { continue }
            let recordName = record.recordID.recordName

            let object: NSManagedObject
            if let existing = existingObject(entityName: entityName, recordName: recordName, in: context) {
                object = existing
            } else {
                object = NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
                context.assign(object, to: sharedStore)
                object.setValue(recordName, forKey: "ckRecordName")
            }
            applyAttributes(from: record, to: object)
            // Preserve the record's CloudKit identity + change tag for safe push updates.
            object.setValue(encodedSystemFields(of: record), forKey: "ckSystemFields")
            byRecordName[recordName] = object
        }

        // Pass 2 — wire to-one relationships (values are parent recordNames).
        for record in records {
            guard let object = byRecordName[record.recordID.recordName] else { continue }
            let entityName = object.entity.name ?? "?"
            for (relName, rel) in object.entity.relationshipsByName where !rel.isToMany {
                guard let parentName = record["CD_\(relName)"] as? String, !parentName.isEmpty else { continue }
                let parent = byRecordName[parentName]
                    ?? existingObject(entityName: rel.destinationEntity?.name ?? "", recordName: parentName, in: context)
                if let parent {
                    object.setValue(parent, forKey: relName)
                } else {
                    daythreadLog.error("SharedSync wire: \(entityName, privacy: .public).\(relName, privacy: .public) → parent recordName \(parentName, privacy: .public) NOT FOUND — orphaned (entity \(rel.destinationEntity?.name ?? "?", privacy: .public))")
                }
            }
        }

        // Deletions — match by ckRecordName across synced entities.
        for recordID in deletions {
            deleteObject(recordName: recordID.recordName, in: context)
        }

        if context.hasChanges { try? context.save() }
    }

    // MARK: — Write path (Core Data → CKRecord)

    /// Encode a local object into its CKRecord, matching NSPCKC's `CD_` format.
    /// Uses the object's stored system fields for an existing record, or mints a new
    /// record in the parent's zone. Caller must have already assigned recordNames to
    /// any new parent objects this one references (push parents before children).
    nonisolated static func ckRecord(for object: NSManagedObject) -> CKRecord? {
        guard let entityName = object.entity.name, syncedEntities.contains(entityName) else { return nil }

        let out: CKRecord
        if let existing = record(fromSystemFields: object.value(forKey: "ckSystemFields") as? Data) {
            out = existing
        } else {
            guard let zoneID = zoneIDForNewChild(of: object) else { return nil }
            let name = (object.value(forKey: "ckRecordName") as? String) ?? UUID().uuidString
            object.setValue(name, forKey: "ckRecordName")
            out = CKRecord(recordType: "CD_\(entityName)", recordID: CKRecord.ID(recordName: name, zoneID: zoneID))
        }

        applyFields(of: object, to: out)
        return out
    }

    /// Set a local object's CD_ fields/relationships onto an existing CKRecord shell.
    /// Used by `ckRecord(for:)` and by conflict resolution (re-applying our edits onto
    /// the server's current record after `.serverRecordChanged`).
    nonisolated static func applyFields(of object: NSManagedObject, to out: CKRecord) {
        out["CD_entityName"] = (object.entity.name ?? "") as CKRecordValue

        for (attrName, attr) in object.entity.attributesByName {
            if skippedAttributes.contains(attrName) { continue }
            let key = "CD_\(attrName)"
            let value = object.value(forKey: attrName)
            switch attr.attributeType {
            case .binaryDataAttributeType:
                if let data = value as? Data, let url = writeTempAsset(data) {
                    out["\(key)_ckAsset"] = CKAsset(fileURL: url)
                }
            case .booleanAttributeType:
                out[key] = (((value as? Bool) == true) ? 1 : 0) as CKRecordValue
            case .UUIDAttributeType:
                if let u = value as? UUID { out[key] = u.uuidString as CKRecordValue }
            default:
                if let v = value as? CKRecordValue { out[key] = v }
            }
        }

        for (relName, rel) in object.entity.relationshipsByName where !rel.isToMany {
            if let parent = object.value(forKey: relName) as? NSManagedObject,
               let parentName = parent.value(forKey: "ckRecordName") as? String {
                out["CD_\(relName)"] = parentName as CKRecordValue
            }
        }
    }

    /// Find the zone for a new (never-synced) object by borrowing it from a related
    /// object that already has system fields (participants only create children of
    /// already-shared objects, so a parent with a known zone always exists).
    nonisolated private static func zoneIDForNewChild(of object: NSManagedObject) -> CKRecordZone.ID? {
        for (relName, rel) in object.entity.relationshipsByName where !rel.isToMany {
            guard let parent = object.value(forKey: relName) as? NSManagedObject else { continue }
            if let rec = record(fromSystemFields: parent.value(forKey: "ckSystemFields") as? Data) {
                return rec.recordID.zoneID
            }
        }
        return nil
    }

    /// Write blob bytes to a temp file for CKAsset upload.
    nonisolated private static func writeTempAsset(_ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { try data.write(to: url); return url } catch { return nil }
    }

    // MARK: — Helpers

    nonisolated private static func applyAttributes(from record: CKRecord, to object: NSManagedObject) {
        for (attrName, attr) in object.entity.attributesByName {
            if skippedAttributes.contains(attrName) { continue }
            let key = "CD_\(attrName)"

            if attr.attributeType == .binaryDataAttributeType {
                if let asset = record["\(key)_ckAsset"] as? CKAsset,
                   let url = asset.fileURL, let data = try? Data(contentsOf: url) {
                    object.setValue(data, forKey: attrName)
                } else if let data = record[key] as? Data {
                    object.setValue(data, forKey: attrName)
                }
                continue
            }

            guard let raw = record[key] else { continue }
            switch attr.attributeType {
            case .UUIDAttributeType:
                if let s = raw as? String, let uuid = UUID(uuidString: s) {
                    object.setValue(uuid, forKey: attrName)
                } else if let u = raw as? UUID {
                    object.setValue(u, forKey: attrName)
                }
            case .booleanAttributeType:
                if let n = raw as? NSNumber {
                    object.setValue(n.boolValue, forKey: attrName)
                }
            default:
                object.setValue(raw, forKey: attrName)
            }
        }
    }

    /// Archive a record's system fields (recordID, zone, change tag) to Data.
    nonisolated static func encodedSystemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        return coder.encodedData
    }

    /// Reconstruct a CKRecord (recordID/zone/change tag, no field values) from
    /// archived system fields. Returns nil if the data is missing or corrupt.
    nonisolated static func record(fromSystemFields data: Data?) -> CKRecord? {
        guard let data else { return nil }
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        let record = CKRecord(coder: coder)
        coder.finishDecoding()
        return record
    }

    nonisolated private static func existingObject(
        entityName: String, recordName: String, in context: NSManagedObjectContext
    ) -> NSManagedObject? {
        guard !entityName.isEmpty else { return nil }
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "ckRecordName == %@", recordName)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    nonisolated private static func deleteObject(recordName: String, in context: NSManagedObjectContext) {
        for entityName in syncedEntities {
            if let object = existingObject(entityName: entityName, recordName: recordName, in: context) {
                context.delete(object)
                return
            }
        }
    }
}
