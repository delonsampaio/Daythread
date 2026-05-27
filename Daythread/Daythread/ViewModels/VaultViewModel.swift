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
        if !isPro && trip.documents.count >= Self.freeDocumentLimit {
            showPaywall = true
            return
        }
        let doc = TripDocument(title: title, documentData: data, mimeType: mimeType)
        doc.trip = trip
        context.insert(doc)
        try? context.save()
    }

    func deleteDocument(_ document: TripDocument, context: ModelContext) {
        context.delete(document)
        try? context.save()
    }

    // MARK: — Expenses

    func addExpense(_ expense: TripExpense, to trip: Trip, context: ModelContext) {
        expense.trip = trip
        context.insert(expense)
        try? context.save()
    }

    func deleteExpense(_ expense: TripExpense, context: ModelContext) {
        context.delete(expense)
        try? context.save()
    }
}
