//
//  VaultViewModel.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import Foundation
import CoreData
import Observation

@Observable
final class VaultViewModel {
    private static let freeDocumentLimit = 5

    var showPaywall: Bool = false

    // MARK: — Documents

    func addDocument(
        title: String,
        data: Data,
        mimeType: String,
        notes: String = "",
        isShared: Bool = false,
        visibleToMemberIDs: String = "",
        isLocked: Bool = true,
        addedByAppleUserID: String = "",
        to trip: Trip,
        isPro: Bool,
        context: NSManagedObjectContext
    ) {
        if !isPro && trip.documentsArray.count >= Self.freeDocumentLimit {
            showPaywall = true
            return
        }
        let doc = TripDocument(context: context)
        doc.id = UUID()
        doc.title = title
        doc.documentData = data
        doc.mimeType = mimeType
        doc.notes = notes
        doc.isShared = isShared
        doc.visibleToMemberIDs = visibleToMemberIDs
        doc.isLocked = isLocked
        doc.addedByAppleUserID = addedByAppleUserID
        doc.addedAt = Date()
        doc.trip = trip
        // Ensure the new document lands in the same persistent store as the trip
        // (shared.sqlite for shared trips) so SharedSyncEngine can push it.
        if let tripStore = trip.objectID.persistentStore {
            context.assign(doc, to: tripStore)
        }
        try? context.save()
    }

    func deleteDocument(_ document: TripDocument, context: NSManagedObjectContext) {
        context.delete(document)
        try? context.save()
    }

    // MARK: — Expenses

    func addExpense(_ expense: TripExpense, to trip: Trip, context: NSManagedObjectContext) {
        expense.trip = trip
        if let tripStore = trip.objectID.persistentStore {
            context.assign(expense, to: tripStore)
        }
        try? context.save()
    }

    func deleteExpense(_ expense: TripExpense, context: NSManagedObjectContext) {
        context.delete(expense)
        try? context.save()
    }

    // MARK: — Expense splitting members

    func addVirtualMember(name: String, to trip: Trip, context: NSManagedObjectContext) {
        let member = TripMember(context: context)
        member.id = UUID()
        member.appleUserID = ""
        member.displayName = name
        member.role = .editor
        member.joinedAt = Date()
        member.trip = trip
        if let tripStore = trip.objectID.persistentStore {
            context.assign(member, to: tripStore)
        }
        try? context.save()
    }

    func removeMember(_ member: TripMember, context: NSManagedObjectContext) {
        context.delete(member)
        try? context.save()
    }

    func settleDebt(
        debtor: TripMember,
        creditor: TripMember,
        amount: Double,
        currencyCode: String,
        trip: Trip,
        context: NSManagedObjectContext
    ) {
        let expense = TripExpense(context: context)
        expense.id = UUID()
        expense.title = "\(debtor.displayName) paid \(creditor.displayName)"
        expense.amount = amount
        expense.currencyCode = currencyCode
        expense.category = .other
        expense.date = Date()
        expense.paidByMemberID = debtor.id
        expense.splitAmongIDs = [creditor.id].compactMap { $0 }
        expense.isSettlement = true
        addExpense(expense, to: trip, context: context)
    }
}
