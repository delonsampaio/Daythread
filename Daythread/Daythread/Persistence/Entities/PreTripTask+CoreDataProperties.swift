import Foundation
import CoreData

extension PreTripTask {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PreTripTask> {
        NSFetchRequest<PreTripTask>(entityName: "PreTripTask")
    }

    @NSManaged public var id: UUID?
    /// Local-only (syncable=NO): CloudKit recordName in the shared zone (SharedSyncEngine).
    @NSManaged public var ckRecordName: String?
    @NSManaged public var title: String
    @NSManaged public var isComplete: Bool
    @NSManaged public var sortOrder: Int
    @NSManaged public var trip: Trip?
}

extension PreTripTask: Identifiable {}
