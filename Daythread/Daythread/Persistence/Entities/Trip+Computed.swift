import Foundation

extension Trip {
    var isUpcoming: Bool { startDate > .now }
    var isCurrent: Bool  { startDate <= .now && endDate >= .now }
    var isPast: Bool     { endDate < .now }
    var durationDays: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: endDate)
            .day.map { $0 + 1 } ?? 1
    }

    // Typed, sorted accessors over the NSSet? relationships.
    var daysArray: [TripDay] {
        (days as? Set<TripDay>)?.sorted { $0.sortOrder < $1.sortOrder } ?? []
    }
    var membersArray: [TripMember] {
        (members as? Set<TripMember>)?.sorted { $0.joinedAt < $1.joinedAt } ?? []
    }
    var documentsArray: [TripDocument] {
        (documents as? Set<TripDocument>)?.sorted { $0.addedAt < $1.addedAt } ?? []
    }
    var expensesArray: [TripExpense] {
        (expenses as? Set<TripExpense>)?.sorted { $0.date < $1.date } ?? []
    }
    var preTripTasksArray: [PreTripTask] {
        (preTripTasks as? Set<PreTripTask>)?.sorted { $0.sortOrder < $1.sortOrder } ?? []
    }
    var lodgingArray: [LodgingInfo] {
        (lodging as? Set<LodgingInfo>)?.sorted { $0.checkIn < $1.checkIn } ?? []
    }
}
