//
//  ExpenseListView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import SwiftData

struct ExpenseListView: View {
    let trip: Trip
    let vm: VaultViewModel

    @Environment(\.modelContext) private var context
    @State private var showAdd = false

    private var expenses: [TripExpense] {
        (trip.expenses ?? []).sorted { $0.date > $1.date }
    }

    private var totalsByCurrency: [String: Double] {
        expenses.reduce(into: [:]) { acc, e in
            acc[e.currencyCode, default: 0] += e.amount
        }
    }

    var body: some View {
        List {
            // Totals header
            if !expenses.isEmpty {
                Section {
                    ForEach(totalsByCurrency.sorted(by: { $0.key < $1.key }), id: \.key) { currency, total in
                        HStack {
                            Text("Total (\(currency))")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ThemeTokens.textSecondary)
                            Spacer()
                            Text(String(format: "%.2f %@", total, currency))
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(ThemeTokens.textPrimary)
                        }
                    }
                }
            }

            // Expense rows
            Section {
                ForEach(expenses) { expense in
                    HStack(spacing: 12) {
                        Image(systemName: expense.category.systemImage)
                            .frame(width: 28)
                            .foregroundStyle(ThemeTokens.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(expense.title)
                                .font(.system(size: 14, weight: .semibold))
                            Text(expense.category.displayName)
                                .font(.caption)
                                .foregroundStyle(ThemeTokens.textSecondary)
                        }
                        Spacer()
                        Text(String(format: "%.2f %@", expense.amount, expense.currencyCode))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    }
                }
                .onDelete { indexSet in
                    indexSet.map { expenses[$0] }.forEach { vm.deleteExpense($0, context: context) }
                }
            }

            // Debt splitting — Pro gate
            Section {
                ProGateOverlay {
                    HStack {
                        Label("Split Expenses", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(ThemeTokens.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(ThemeTokens.textMuted)
                    }
                    .padding(12)
                    .background(ThemeTokens.backgroundCard)
                    .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.cardCornerRadius))
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddExpenseSheet(trip: trip, vm: vm)
        }
    }
}
