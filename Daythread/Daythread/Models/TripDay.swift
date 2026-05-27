//
//  TripDay.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import Foundation
import SwiftData

@Model
final class TripDay {
    var id: UUID
    var date: Date
    var sortOrder: Int   // @Query sort key — NOT date
    var notes: String

    @Relationship(deleteRule: .cascade) var events: [TripEvent]
    var trip: Trip?

    init(
        id: UUID = UUID(),
        date: Date,
        sortOrder: Int,
        notes: String = ""
    ) {
        self.id = id
        self.date = date
        self.sortOrder = sortOrder
        self.notes = notes
        self.events = []
    }
}
