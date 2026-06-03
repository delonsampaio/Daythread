import Foundation
import CoreData

extension TripDocument {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TripDocument> {
        NSFetchRequest<TripDocument>(entityName: "TripDocument")
    }

    @NSManaged public var id: UUID?
    /// Local-only (syncable=NO): CloudKit recordName in the shared zone (SharedSyncEngine).
    @NSManaged public var ckRecordName: String?
    @NSManaged public var title: String
    @NSManaged public var documentData: Data?
    @NSManaged public var mimeType: String
    @NSManaged public var expiryDate: Date?
    @NSManaged public var addedAt: Date
    /// When true, co-editors on a shared trip can see this document.
    /// Defaults to false so sensitive docs (passports etc.) are private.
    @NSManaged public var isShared: Bool
    /// When true, only the originator (addedByAppleUserID) can edit the document.
    /// Defaults to true so documents are protected immediately after creation.
    @NSManaged public var isLocked: Bool
    /// Free-text note attached to the document (e.g. visa requirements, booking refs).
    @NSManaged public var notes: String
    /// CloudKit user record name of the person who added this document.
    /// Used to show the owner their own private docs regardless of isShared.
    @NSManaged public var addedByAppleUserID: String
    @NSManaged public var trip: Trip?
}

extension TripDocument: Identifiable {}
