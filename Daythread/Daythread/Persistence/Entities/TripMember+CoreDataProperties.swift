import Foundation
import CoreData

extension TripMember {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TripMember> {
        NSFetchRequest<TripMember>(entityName: "TripMember")
    }

    @NSManaged public var id: UUID?
    /// Local-only (syncable=NO): CloudKit recordName in the shared zone (SharedSyncEngine).
    @NSManaged public var ckRecordName: String?
    /// Local-only (syncable=NO): archived CKRecord system fields for push updates.
    @NSManaged public var ckSystemFields: Data?
    @NSManaged public var appleUserID: String
    @NSManaged public var displayName: String
    @NSManaged public var roleRaw: String
    @NSManaged public var avatarData: Data?
    @NSManaged public var joinedAt: Date
    @NSManaged public var trip: Trip?
}

extension TripMember: Identifiable {}
