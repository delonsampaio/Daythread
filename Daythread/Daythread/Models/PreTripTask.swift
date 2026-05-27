//
//  PreTripTask.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//
//  CloudKit compliance: inline property defaults on all non-optional stored properties.
//

import Foundation
import SwiftData

@Model
final class PreTripTask {
    var id: UUID = UUID()
    var title: String = ""
    var isComplete: Bool = false
    var sortOrder: Int = 0

    var trip: Trip?

    init(
        id: UUID = UUID(),
        title: String,
        isComplete: Bool = false,
        sortOrder: Int
    ) {
        self.id = id
        self.title = title
        self.isComplete = isComplete
        self.sortOrder = sortOrder
    }
}
