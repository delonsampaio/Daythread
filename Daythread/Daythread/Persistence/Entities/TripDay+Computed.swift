import Foundation
import CoreData

extension TripDay {
    var eventsArray: [TripEvent] {
        (events as? Set<TripEvent>)?.filter { !$0.isDeleted }
            .sorted { $0.sortOrder < $1.sortOrder } ?? []
    }
}
