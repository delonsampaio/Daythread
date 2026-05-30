import Foundation
import CoreData

extension Trip {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Trip> {
        NSFetchRequest<Trip>(entityName: "Trip")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var destination: String?
    @NSManaged public var startDate: Date?
    @NSManaged public var endDate: Date?
    @NSManaged public var coverImageData: Data?
    @NSManaged public var cloudKitShareID: String?
    @NSManaged public var isArchived: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var gradientSeed: Int64
    @NSManaged public var days: NSSet?
    @NSManaged public var members: NSSet?
    @NSManaged public var documents: NSSet?
    @NSManaged public var expenses: NSSet?
    @NSManaged public var preTripTasks: NSSet?
    @NSManaged public var lodging: NSSet?
}

extension Trip: Identifiable {}
