//
//  LodgingInfo.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import Foundation
import SwiftData

@Model
final class LodgingInfo {
    var id: UUID
    var name: String
    var address: String
    var checkIn: Date
    var checkOut: Date
    var confirmationNumber: String
    var notes: String

    var trip: Trip?   // pinned to trip, not to a single day

    init(
        id: UUID = UUID(),
        name: String,
        address: String = "",
        checkIn: Date,
        checkOut: Date,
        confirmationNumber: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.checkIn = checkIn
        self.checkOut = checkOut
        self.confirmationNumber = confirmationNumber
        self.notes = notes
    }
}
