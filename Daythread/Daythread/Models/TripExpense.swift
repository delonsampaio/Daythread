//
//  TripExpense.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//
//  CloudKit compliance: inline property defaults on all non-optional stored properties.
//  splitAmongStringIDs is [String] rather than [UUID] because CloudKit natively
//  supports List<String> but not UUID arrays — SwiftData's opaque [UUID] serialisation
//  is notorious for silent sync failures and merge conflicts on multi-device trips.
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

    /// Stored as [String] for CloudKit compatibility (native List<String>).
    /// Always an explicit snapshot of who was included at save time — never empty.
    /// Use the splitAmongIDs computed property for UUID-based access in Swift code.
    var splitAmongStringIDs: [String] = []

    var notes: String = ""
    /// JPEG receipt photo. Stored outside SQLite via externalStorage to keep
    /// ExpenseListView fetches fast regardless of how many receipts are attached.
    @Attribute(.externalStorage) var receiptImageData: Data?

    var trip: Trip?

    /// Computed UUID convenience — wraps splitAmongStringIDs.
    /// Not stored; SwiftData only persists splitAmongStringIDs.
    var splitAmongIDs: [UUID] {
        get { splitAmongStringIDs.compactMap { UUID(uuidString: $0) } }
        set { splitAmongStringIDs = newValue.map { $0.uuidString } }
    }

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
        self.splitAmongStringIDs = splitAmongIDs.map { $0.uuidString }
        self.notes = notes
        self.receiptImageData = receiptImageData
    }
}
