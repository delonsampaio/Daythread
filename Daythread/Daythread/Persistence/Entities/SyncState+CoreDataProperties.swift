import Foundation
import CoreData

extension SyncState {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<SyncState> {
        NSFetchRequest<SyncState>(entityName: "SyncState")
    }

    @NSManaged public var zoneName: String?
    @NSManaged public var ownerName: String?
    @NSManaged public var changeTokenData: Data?
    @NSManaged public var lastSyncedAt: Date?
    @NSManaged public var databaseScope: String
}

extension SyncState: Identifiable {}
