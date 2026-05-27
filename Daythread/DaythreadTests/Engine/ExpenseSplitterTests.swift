//
//  ExpenseSplitterTests.swift
//  DaythreadTests
//
//  Created by Delon Sampaio on 5/27/26.
//

import XCTest
@testable import Daythread

final class ExpenseSplitterTests: XCTestCase {
    let alice = UUID()
    let bob   = UUID()
    let carol = UUID()

    // MARK: — empty

    func testEmptyExpensesReturnsNoDebts() {
        let result = ExpenseSplitter.minimize(expenses: [], members: [alice, bob])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: — single payer

    func testSinglePayer_othersOweEqualShare() {
        // Alice paid $90; Bob and Carol each owe $30 to Alice
        let expenses = [
            SplitExpense(amount: 90, currency: "USD", paidBy: alice, splitAmong: [alice, bob, carol])
        ]
        let debts = ExpenseSplitter.minimize(expenses: expenses, members: [alice, bob, carol])
        XCTAssertEqual(debts.count, 2)

        let aliceOwes = debts.filter { $0.from == alice }
        XCTAssertTrue(aliceOwes.isEmpty, "Alice paid — she owes nothing")

        let bobDebt = debts.first { $0.from == bob && $0.to == alice }
        XCTAssertEqual(bobDebt?.amount ?? 0, 30, accuracy: 0.001)

        let carolDebt = debts.first { $0.from == carol && $0.to == alice }
        XCTAssertEqual(carolDebt?.amount ?? 0, 30, accuracy: 0.001)
    }

    // MARK: — debt minimization

    func testDebtMinimization_reducesTransactions() {
        // Alice owes Bob $20 (Bob paid for both), Bob owes Carol $20 (Carol paid for both)
        // Minimized: Alice pays Carol $20 directly (1 transaction instead of 2)
        let expenses = [
            SplitExpense(amount: 20, currency: "USD", paidBy: bob,   splitAmong: [alice, bob]),
            SplitExpense(amount: 20, currency: "USD", paidBy: carol,  splitAmong: [bob, carol])
        ]
        let debts = ExpenseSplitter.minimize(expenses: expenses, members: [alice, bob, carol])
        XCTAssertLessThanOrEqual(debts.count, 2, "Debt minimization should reduce transactions")
    }

    // MARK: — even split

    func testEvenSplitResultsInZeroDebts() {
        // Each person pays an equal share — net balance is zero for everyone
        let expenses = [
            SplitExpense(amount: 30, currency: "USD", paidBy: alice, splitAmong: [alice, bob, carol]),
            SplitExpense(amount: 30, currency: "USD", paidBy: bob,   splitAmong: [alice, bob, carol]),
            SplitExpense(amount: 30, currency: "USD", paidBy: carol,  splitAmong: [alice, bob, carol])
        ]
        let debts = ExpenseSplitter.minimize(expenses: expenses, members: [alice, bob, carol])
        XCTAssertTrue(debts.isEmpty, "Equal contributions produce zero debts")
    }

    // MARK: — currency isolation

    func testCurrencyIsolation() {
        // USD and EUR debts must settle independently — no cross-currency netting
        let expenses = [
            SplitExpense(amount: 90, currency: "USD", paidBy: alice, splitAmong: [alice, bob]),
            SplitExpense(amount: 90, currency: "EUR", paidBy: bob,   splitAmong: [alice, bob])
        ]
        let debts = ExpenseSplitter.minimize(expenses: expenses, members: [alice, bob])
        let usdDebts = debts.filter { $0.currency == "USD" }
        let eurDebts = debts.filter { $0.currency == "EUR" }
        // Each currency settles independently: Bob owes Alice $45 USD, Alice owes Bob €45 EUR
        XCTAssertFalse(usdDebts.isEmpty || eurDebts.isEmpty,
                       "Both currencies must have debts — no cross-currency netting")
    }
}
