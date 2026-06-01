import Foundation
import CoreData

extension Trip {
    var isUpcoming: Bool { startDate > .now }
    var isCurrent: Bool  { startDate <= .now && endDate >= .now }
    var isPast: Bool     { endDate < .now }
    var durationDays: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: endDate)
            .day.map { $0 + 1 } ?? 1
    }

    // Typed, sorted accessors over the NSSet? relationships. Deleted objects are
    // filtered out: when a trip (or the whole graph) is deleted, observing views
    // re-render for one pass while the cascade-deleted children still linger in
    // the relationship set — reading a non-optional @NSManaged value on a deleted
    // object traps in _unconditionallyBridgeFromObjectiveC.
    var daysArray: [TripDay] {
        (days as? Set<TripDay>)?.filter { !$0.isDeleted }
            .sorted { $0.sortOrder < $1.sortOrder } ?? []
    }
    var membersArray: [TripMember] {
        (members as? Set<TripMember>)?.filter { !$0.isDeleted }
            .sorted { $0.joinedAt < $1.joinedAt } ?? []
    }
    var documentsArray: [TripDocument] {
        (documents as? Set<TripDocument>)?.filter { !$0.isDeleted }
            .sorted { $0.addedAt < $1.addedAt } ?? []
    }
    var expensesArray: [TripExpense] {
        (expenses as? Set<TripExpense>)?.filter { !$0.isDeleted }
            .sorted { $0.date < $1.date } ?? []
    }
    var preTripTasksArray: [PreTripTask] {
        (preTripTasks as? Set<PreTripTask>)?.filter { !$0.isDeleted }
            .sorted { $0.sortOrder < $1.sortOrder } ?? []
    }
    var lodgingArray: [LodgingInfo] {
        (lodging as? Set<LodgingInfo>)?.filter { !$0.isDeleted }
            .sorted { $0.checkIn < $1.checkIn } ?? []
    }
}
