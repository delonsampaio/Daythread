//
//  TripDay.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//
//  CloudKit compliance: inline property defaults; events: [TripEvent]? (CloudKit requires optional relationships).
//

import Foundation
import SwiftData

@Model
final class TripDay {
    var id: UUID = UUID()
    var date: Date = Date.now
    var sortOrder: Int = 0   // @Query sort key — NOT date
    var notes: String = ""

    @Relationship(deleteRule: .cascade) var events: [TripEvent]?
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
