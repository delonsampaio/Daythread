//
//  VaultViewModel.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import Foundation
import SwiftData
import Observation

@Observable
final class VaultViewModel {
    private static let freeDocumentLimit = 5

    // Set by VaultView when paywall needs to appear
    var showPaywall: Bool = false

    // MARK: — Documents

    func addDocument(
        title: String,
        data: Data,
        mimeType: String,
        to trip: Trip,
        isPro: Bool,
        context: ModelContext
    ) {
        if !isPro && (trip.documents ?? []).count >= Self.freeDocumentLimit {
            showPaywall = true
            return
        }
        let doc = TripDocument(title: title, documentData: data, mimeType: mimeType)
        context.insert(doc)
        doc.trip = trip
        try? context.save()
    }

    func deleteDocument(_ document: TripDocument, context: ModelContext) {
        context.delete(document)
        try? context.save()
    }

    // MARK: — Expenses

    func addExpense(_ expense: TripExpense, to trip: Trip, context: ModelContext) {
        context.insert(expense)
        expense.trip = trip
        try? context.save()
    }

    func deleteExpense(_ expense: TripExpense, context: ModelContext) {
        context.delete(expense)
        try? context.save()
    }

    // MARK: — Expense splitting members

    /// Adds a virtual (shadow) TripMember for expense-splitting purposes.
    /// Virtual members have an empty appleUserID and can later be linked
    /// to a real iCloud account when the person joins via CloudKit.
    func addVirtualMember(name: String, to trip: Trip, context: ModelContext) {
        let member = TripMember(appleUserID: "", displayName: name, role: .editor)
        context.insert(member)
        member.trip = trip
        try? context.save()
    }

    func removeMember(_ member: TripMember, context: ModelContext) {
        context.delete(member)
        try? context.save()
    }

    /// Creates a settlement expense recording that `debtor` paid `creditor`.
    /// Inserting this expense into the trip makes the algorithm recompute
    /// and zeroes the debt automatically — no separate settlements table needed.
    func settleDebt(
        debtor: TripMember,
        creditor: TripMember,
        amount: Double,
        currencyCode: String,
        trip: Trip,
        context: ModelContext
    ) {
        let expense = TripExpense(
            title: "\(debtor.displayName) paid \(creditor.displayName)",
            amount: amount,
            currencyCode: currencyCode,
            category: .other,
            paidByMemberID: debtor.id,
            splitAmongIDs: [creditor.id]
        )
        addExpense(expense, to: trip, context: context)
    }
}
