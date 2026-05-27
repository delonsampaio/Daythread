//
//  ExpenseSplitter.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/27/26.
//
//  Pure Engine struct — no SwiftUI/SwiftData imports.
//  Implements greedy debt-minimization: computes net balances per currency
//  then resolves them with the fewest transactions possible.

import Foundation

// MARK: — Input / Output types
//
// nonisolated on all stored properties — these are pure data structs that must be
// accessible from any actor context (SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor would
// otherwise infer @MainActor, breaking access from nonisolated XCTAssert autoclosures).

struct SplitExpense: Sendable {
    nonisolated let amount: Double
    nonisolated let currency: String
    nonisolated let paidBy: UUID
    nonisolated let splitAmong: [UUID]
}

struct Debt: Sendable {
    nonisolated let from: UUID
    nonisolated let to: UUID
    nonisolated let amount: Double
    nonisolated let currency: String
}

// MARK: — Engine

struct ExpenseSplitter {

    /// Returns the minimum set of payments that settles all debts.
    nonisolated static func minimize(
        expenses: [SplitExpense],
        members: [UUID]
    ) -> [Debt] {
        guard !expenses.isEmpty else { return [] }

        // Group expenses by currency and settle each independently
        let currencies = Set(expenses.map(\.currency))
        return currencies.flatMap { currency -> [Debt] in
            let forCurrency = expenses.filter { $0.currency == currency }
            return settle(expenses: forCurrency, currency: currency)
        }
    }

    // MARK: — Private

    /// Greedy minimization for a single currency.
    /// 1. Compute each member's net balance (positive = owed money, negative = owes money).
    /// 2. Greedily match the largest creditor with the largest debtor.
    private nonisolated static func settle(
        expenses: [SplitExpense],
        currency: String
    ) -> [Debt] {
        // Build net balance map: positive → creditor, negative → debtor
        var balance: [UUID: Double] = [:]
        for expense in expenses {
            guard !expense.splitAmong.isEmpty else { continue }
            let share = expense.amount / Double(expense.splitAmong.count)
            // Payer receives credit for the full amount
            balance[expense.paidBy, default: 0] += expense.amount
            // Each participant owes their share
            for participant in expense.splitAmong {
                balance[participant, default: 0] -= share
            }
        }

        // Separate into creditors (balance > 0) and debtors (balance < 0)
        var creditors = balance.filter { $0.value > 1e-9 }.map { ($0.key, $0.value) }
                              .sorted { $0.1 > $1.1 }  // largest first
        var debtors   = balance.filter { $0.value < -1e-9 }.map { ($0.key, -$0.value) }
                              .sorted { $0.1 > $1.1 }  // largest debt first

        var debts: [Debt] = []

        var ci = 0  // creditor index
        var di = 0  // debtor index

        while ci < creditors.count && di < debtors.count {
            let (creditor, credit) = creditors[ci]
            let (debtor, debt)     = debtors[di]

            let payment = min(credit, debt)
            if payment > 1e-9 {
                debts.append(Debt(from: debtor, to: creditor, amount: payment, currency: currency))
            }

            creditors[ci].1 -= payment
            debtors[di].1   -= payment

            if creditors[ci].1 < 1e-9 { ci += 1 }
            if debtors[di].1   < 1e-9 { di += 1 }
        }

        return debts
    }
}
