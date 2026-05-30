import Foundation

extension TripEvent {
    var category: EventCategory {
        get { EventCategory(rawValue: categoryRaw) ?? .activity }
        set { categoryRaw = newValue.rawValue }
    }
}
