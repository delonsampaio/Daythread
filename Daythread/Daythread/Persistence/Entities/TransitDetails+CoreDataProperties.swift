import Foundation
import CoreData

extension TransitDetails {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TransitDetails> {
        NSFetchRequest<TransitDetails>(entityName: "TransitDetails")
    }

    @NSManaged public var id: UUID?
    /// Local-only (syncable=NO): CloudKit recordName in the shared zone (SharedSyncEngine).
    @NSManaged public var ckRecordName: String?
    /// Local-only (syncable=NO): archived CKRecord system fields for push updates.
    @NSManaged public var ckSystemFields: Data?
    @NSManaged public var carrier: String
    @NSManaged public var flightOrTrainNumber: String
    @NSManaged public var pnr: String
    @NSManaged public var departureCode: String
    @NSManaged public var arrivalCode: String
    @NSManaged public var departureName: String
    @NSManaged public var arrivalName: String
    @NSManaged public var departureTerminal: String?
    @NSManaged public var arrivalTerminal: String?
    @NSManaged public var departureGate: String?
    @NSManaged public var arrivalGate: String?
    @NSManaged public var seatNumber: String?
    @NSManaged public var baggageClaim: String?
    @NSManaged public var departureTZIdentifier: String
    @NSManaged public var arrivalTZIdentifier: String
    @NSManaged public var event: TripEvent?
}

extension TransitDetails: Identifiable {}
