import Foundation
import CoreData

extension SyncPing {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<SyncPing> {
        NSFetchRequest<SyncPing>(entityName: "SyncPing")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var updatedAt: Date?
}

extension SyncPing: Identifiable {}
