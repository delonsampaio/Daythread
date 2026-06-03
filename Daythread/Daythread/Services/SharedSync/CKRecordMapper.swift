import CloudKit
import CoreData

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

    /// Device-local / engine-internal attributes that must never be imported.
    nonisolated private static let skippedAttributes: Set<String> = [
        "ckRecordName", "ekEventIdentifier", "hasReminder", "showInCalendar"
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
            byRecordName[recordName] = object
        }

        // Pass 2 — wire to-one relationships (values are parent recordNames).
        for record in records {
            guard let object = byRecordName[record.recordID.recordName] else { continue }
            for (relName, rel) in object.entity.relationshipsByName where !rel.isToMany {
                guard let parentName = record["CD_\(relName)"] as? String, !parentName.isEmpty else { continue }
                let parent = byRecordName[parentName]
                    ?? existingObject(entityName: rel.destinationEntity?.name ?? "", recordName: parentName, in: context)
                if let parent { object.setValue(parent, forKey: relName) }
            }
        }

        // Deletions — match by ckRecordName across synced entities.
        for recordID in deletions {
            deleteObject(recordName: recordID.recordName, in: context)
        }

        if context.hasChanges { try? context.save() }
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
