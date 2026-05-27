//
//  PreTripTask.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import Foundation
import SwiftData

@Model
final class PreTripTask {
    var id: UUID
    var title: String
    var isComplete: Bool
    var sortOrder: Int

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
