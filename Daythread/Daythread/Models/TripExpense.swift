//
//  TripExpense.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import Foundation
import SwiftData

@Model
final class TripExpense {
    var id: UUID
    var title: String
    var amount: Double
    var currencyCode: String        // ISO 4217 — "EUR", "USD"
    var category: ExpenseCategory
    var date: Date
    var paidByMemberID: UUID?       // nil = current user
    var notes: String

    var trip: Trip?

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        currencyCode: String = "USD",
        category: ExpenseCategory = .other,
        date: Date = Date(),
        paidByMemberID: UUID? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.currencyCode = currencyCode
        self.category = category
        self.date = date
        self.paidByMemberID = paidByMemberID
        self.notes = notes
    }
}
