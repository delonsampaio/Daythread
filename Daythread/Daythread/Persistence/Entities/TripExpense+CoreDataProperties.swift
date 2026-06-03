import Foundation
import CoreData

extension TripExpense {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TripExpense> {
        NSFetchRequest<TripExpense>(entityName: "TripExpense")
    }

    @NSManaged public var id: UUID?
    /// Local-only (syncable=NO): CloudKit recordName in the shared zone (SharedSyncEngine).
    @NSManaged public var ckRecordName: String?
    @NSManaged public var title: String
    @NSManaged public var amount: Double
    @NSManaged public var currencyCode: String
    @NSManaged public var categoryRaw: String
    @NSManaged public var date: Date
    @NSManaged public var paidByMemberID: UUID?
    @NSManaged public var splitAmongJoined: String
    @NSManaged public var notes: String
    @NSManaged public var receiptImageData: Data?
    @NSManaged public var isSettlement: Bool
    @NSManaged public var trip: Trip?
}

extension TripExpense: Identifiable {}
