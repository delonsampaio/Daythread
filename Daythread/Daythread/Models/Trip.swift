//
//  Trip.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import Foundation
import SwiftData

@Model
final class Trip {
    var id: UUID
    var name: String
    var destination: String
    var startDate: Date
    var endDate: Date
    @Attribute(.externalStorage) var coverImageData: Data?
    var cloudKitShareID: String?
    var isArchived: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade) var days: [TripDay]
    @Relationship(deleteRule: .cascade) var members: [TripMember]
    @Relationship(deleteRule: .cascade) var documents: [TripDocument]
    @Relationship(deleteRule: .cascade) var expenses: [TripExpense]
    @Relationship(deleteRule: .cascade) var preTripTasks: [PreTripTask]
    @Relationship(deleteRule: .cascade) var lodging: [LodgingInfo]

    // Computed — not persisted
    var isUpcoming: Bool { startDate > .now }
    var isCurrent: Bool  { startDate <= .now && endDate >= .now }
    var isPast: Bool     { endDate < .now }
    var durationDays: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: endDate).day.map { $0 + 1 } ?? 1
    }

    init(
        id: UUID = UUID(),
        name: String,
        destination: String,
        startDate: Date,
        endDate: Date,
        coverImageData: Data? = nil,
        cloudKitShareID: String? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.coverImageData = coverImageData
        self.cloudKitShareID = cloudKitShareID
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.days = []
        self.members = []
        self.documents = []
        self.expenses = []
        self.preTripTasks = []
        self.lodging = []
    }
}
