//
//  TripEvent.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import Foundation
import SwiftData

@Model
final class TripEvent {
    var id: UUID
    var title: String
    var startTime: Date?
    var endTime: Date?
    var location: String?
    var latitude: Double?
    var longitude: Double?
    var category: EventCategory   // the currency
    var isTimeLocked: Bool
    var sortOrder: Int            // @Query sort key — NOT startTime
    var notes: String

    @Relationship(deleteRule: .cascade) var transitDetails: TransitDetails?
    var day: TripDay?

    init(
        id: UUID = UUID(),
        title: String,
        startTime: Date? = nil,
        endTime: Date? = nil,
        location: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        category: EventCategory = .activity,
        isTimeLocked: Bool = false,
        sortOrder: Int,
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
        self.isTimeLocked = isTimeLocked
        self.sortOrder = sortOrder
        self.notes = notes
    }
}
