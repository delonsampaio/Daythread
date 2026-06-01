import Foundation
import CoreData

extension TripDay {
    var eventsArray: [TripEvent] {
        (events as? Set<TripEvent>)?.filter { $0.isAlive }
            .sorted { $0.sortOrder < $1.sortOrder } ?? []
    }
}
