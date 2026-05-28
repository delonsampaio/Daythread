//
//  TripExpense.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//
//  CloudKit compliance: inline property defaults on all non-optional stored properties.
//

import Foundation
import SwiftData

@Model
final class TripExpense {
    var id: UUID = UUID()
    var title: String = ""
    var amount: Double = 0.0
    var currencyCode: String = "USD"        // ISO 4217 — "EUR", "USD"
    var category: ExpenseCategory = ExpenseCategory.other
    var date: Date = Date.now
    var paidByMemberID: UUID?       // TripMember.id of who paid; nil = untracked
    /// IDs of TripMembers included in the split. Empty = split among ALL trip members.
    var splitAmongIDs: [UUID] = []
    var notes: String = ""
    /// JPEG receipt photo. Stored outside SQLite via externalStorage to keep
    /// ExpenseListView fetches fast regardless of how many receipts are attached.
    @Attribute(.externalStorage) var receiptImageData: Data?

    var trip: Trip?

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        currencyCode: String = "USD",
        category: ExpenseCategory = .other,
        date: Date = Date(),
        paidByMemberID: UUID? = nil,
        splitAmongIDs: [UUID] = [],
        notes: String = "",
        receiptImageData: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.currencyCode = currencyCode
        self.category = category
        self.date = date
        self.paidByMemberID = paidByMemberID
        self.splitAmongIDs = splitAmongIDs
        self.notes = notes
        self.receiptImageData = receiptImageData
    }
}
