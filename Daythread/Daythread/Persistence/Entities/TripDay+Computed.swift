import Foundation

extension TripDay {
    var eventsArray: [TripEvent] {
        (events as? Set<TripEvent>)?.sorted { $0.sortOrder < $1.sortOrder } ?? []
    }
}
