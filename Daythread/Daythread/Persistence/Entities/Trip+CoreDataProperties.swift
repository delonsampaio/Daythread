import Foundation
import CoreData

extension Trip {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Trip> {
        NSFetchRequest<Trip>(entityName: "Trip")
    }

    // Always-set / defaulted attributes are declared non-optional to match the
    // app's existing call sites. Genuinely-optional attributes stay Optional.
    @NSManaged public var id: UUID?
    /// Local-only (syncable=NO): the CloudKit recordName of this object in the shared
    /// zone. Used by SharedSyncEngine to resolve relationships and target push updates.
    @NSManaged public var ckRecordName: String?
    /// Local-only (syncable=NO): archived CKRecord system fields (recordID, zone,
    /// change tag) for safe .ifServerRecordUnchanged updates on push.
    @NSManaged public var ckSystemFields: Data?
    @NSManaged public var name: String
    @NSManaged public var destination: String
    @NSManaged public var startDate: Date
    @NSManaged public var endDate: Date
    @NSManaged public var coverImageData: Data?
    @NSManaged public var cloudKitShareID: String?
    @NSManaged public var isArchived: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var gradientSeed: Int
    @NSManaged public var migrationState: Int16
    @NSManaged public var days: NSSet?
    @NSManaged public var members: NSSet?
    @NSManaged public var documents: NSSet?
    @NSManaged public var expenses: NSSet?
    @NSManaged public var preTripTasks: NSSet?
    @NSManaged public var lodging: NSSet?
}

extension Trip: Identifiable {}

// MARK: - Migration State

enum TripMigrationState: Int16 {
    case none = 0      // lives in NSPCKC store, never shared via custom engine
    case cloned = 1    // graph duplicated into shared store, not yet uploaded
    case uploaded = 2  // pushed to custom zone, NSPCKC originals not yet purged
    case done = 3      // fully on the custom store
}

extension Trip {
    var migration: TripMigrationState {
        get { TripMigrationState(rawValue: migrationState) ?? .none }
        set { migrationState = newValue.rawValue }
    }
}
