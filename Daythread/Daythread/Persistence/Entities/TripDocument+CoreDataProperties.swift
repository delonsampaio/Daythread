import Foundation
import CoreData

extension TripDocument {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TripDocument> {
        NSFetchRequest<TripDocument>(entityName: "TripDocument")
    }

    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var documentData: Data?
    @NSManaged public var mimeType: String
    @NSManaged public var expiryDate: Date?
    @NSManaged public var addedAt: Date
    @NSManaged public var trip: Trip?
}

extension TripDocument: Identifiable {}
