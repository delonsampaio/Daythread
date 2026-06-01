import Foundation
import CoreData

extension TripDay {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TripDay> {
        NSFetchRequest<TripDay>(entityName: "TripDay")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var date: Date
    @NSManaged public var sortOrder: Int
    @NSManaged public var notes: String
    @NSManaged public var events: NSSet?
    @NSManaged public var trip: Trip?
}

extension TripDay: Identifiable {}
