import Foundation
import CoreData

extension TripEvent {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TripEvent> {
        NSFetchRequest<TripEvent>(entityName: "TripEvent")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var startTime: Date?
    @NSManaged public var endTime: Date?
    @NSManaged public var location: String?
    @NSManaged public var latitude: Double
    @NSManaged public var longitude: Double
    @NSManaged public var categoryRaw: String
    @NSManaged public var isTimeLocked: Bool
    @NSManaged public var sortOrder: Int
    @NSManaged public var notes: String
    /// Device-local EKEvent identifier — not synced to CloudKit (syncable="NO").
    /// Each device manages its own Apple Calendar entries independently.
    @NSManaged public var ekEventIdentifier: String
    /// Whether this event should appear in the user's Apple Calendar (device-local, not synced to CloudKit).
    @NSManaged public var showInCalendar: Bool
    @NSManaged public var day: TripDay?
    @NSManaged public var transitDetails: TransitDetails?
}

extension TripEvent: Identifiable {}
