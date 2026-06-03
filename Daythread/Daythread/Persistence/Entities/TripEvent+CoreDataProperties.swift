import Foundation
import CoreData

extension TripEvent {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TripEvent> {
        NSFetchRequest<TripEvent>(entityName: "TripEvent")
    }

    @NSManaged public var id: UUID?
    /// Local-only (syncable=NO): CloudKit recordName in the shared zone (SharedSyncEngine).
    @NSManaged public var ckRecordName: String?
    /// Local-only (syncable=NO): archived CKRecord system fields for push updates.
    @NSManaged public var ckSystemFields: Data?
    @NSManaged public var addedByAppleUserID: String
    @NSManaged public var isPrivate: Bool
    /// Comma-separated CloudKit user record names of members (besides the originator)
    /// who can see this event when isPrivate=true. Empty = only the originator sees it.
    /// Synced (syncable=YES) so all devices enforce the same visibility.
    @NSManaged public var visibleToMemberIDs: String
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
    /// Whether to fire a reminder for this event (device-local, not synced to CloudKit).
    /// Only active when the global reminder toggle is on in Settings.
    @NSManaged public var hasReminder: Bool
    /// Whether this event should appear in the user's Apple Calendar (device-local, not synced to CloudKit).
    @NSManaged public var showInCalendar: Bool
    @NSManaged public var day: TripDay?
    @NSManaged public var transitDetails: TransitDetails?
}

extension TripEvent: Identifiable {}

extension TripEvent {
    /// The event's absolute start time, combining the trip day's calendar date
    /// with the time component of `startTime` in the given timezone.
    /// Returns nil if the event is untimed or has no assigned day.
    func eventStart(in timezone: TimeZone = .current) -> Date? {
        guard let dayDate = day?.date, let rawTime = startTime else { return nil }
        return combining(dayDate: dayDate, time: rawTime, in: timezone)
    }

    /// The event's absolute end time on the trip day's date.
    /// If end is before start (overnight crossing), advances by one day.
    /// Returns nil if the event has no end time or no assigned day.
    func eventEnd(in timezone: TimeZone = .current) -> Date? {
        guard let dayDate = day?.date, let rawEnd = endTime else { return nil }
        let end = combining(dayDate: dayDate, time: rawEnd, in: timezone)
        if let start = eventStart(in: timezone), let end, end < start {
            return Calendar.current.date(byAdding: .day, value: 1, to: end)
        }
        return end
    }

    private func combining(dayDate: Date, time: Date, in timezone: TimeZone) -> Date? {
        var cal = Calendar.current
        cal.timeZone = timezone
        let d = cal.dateComponents([.year, .month, .day], from: dayDate)
        let t = cal.dateComponents([.hour, .minute], from: time)
        var combined = DateComponents()
        combined.year = d.year;   combined.month  = d.month;  combined.day    = d.day
        combined.hour = t.hour;   combined.minute = t.minute; combined.timeZone = timezone
        return cal.date(from: combined)
    }
}
