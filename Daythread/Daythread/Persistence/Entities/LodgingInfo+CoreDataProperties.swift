import Foundation
import CoreData

extension LodgingInfo {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LodgingInfo> {
        NSFetchRequest<LodgingInfo>(entityName: "LodgingInfo")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String
    @NSManaged public var address: String
    @NSManaged public var checkIn: Date
    @NSManaged public var checkOut: Date
    @NSManaged public var confirmationNumber: String
    @NSManaged public var notes: String
    @NSManaged public var trip: Trip?
}

extension LodgingInfo: Identifiable {}
