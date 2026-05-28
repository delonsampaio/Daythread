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
    @Environment(TripStore.self) private var store
    @State private var showAdd = false
    @State private var showSplit = false
    @State private var viewingReceiptData: Data?

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
                            HStack(spacing: 4) {
                                Text(expense.category.displayName)
                                    .font(.caption)
                                    .foregroundStyle(ThemeTokens.textSecondary)
                                if let payerID = expense.paidByMemberID,
                                   let name = (trip.members ?? []).first(where: { $0.id == payerID })?.displayName {
                                    Text("·")
                                        .font(.caption)
                                        .foregroundStyle(ThemeTokens.textMuted)
                                    Text("pd \(name)")
                                        .font(.caption)
                                        .foregroundStyle(ThemeTokens.textMuted)
                                }
                            }
                        }
                        Spacer()
                        Text(String(format: "%.2f %@", expense.amount, expense.currencyCode))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))

                        if let data = expense.receiptImageData, let uiImage = UIImage(data: data) {
                            Button {
                                viewingReceiptData = data
                            } label: {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .onDelete { indexSet in
                    indexSet.map { expenses[$0] }.forEach { vm.deleteExpense($0, context: context) }
                }
            }

        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard store.isPro else { vm.showPaywall = true; return }
                    showSplit = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddExpenseSheet(trip: trip, vm: vm)
        }
        .sheet(isPresented: $showSplit) {
            SplitExpensesSheet(trip: trip, vm: vm)
        }
        .sheet(item: Binding(
            get: { viewingReceiptData.map { ReceiptWrapper(data: $0) } },
            set: { _ in viewingReceiptData = nil }
        )) { wrapper in
            ReceiptViewerSheet(imageData: wrapper.data)
        }
    }
}

// MARK: — Receipt viewer

private struct ReceiptWrapper: Identifiable {
    let id = UUID()
    let data: Data
}

private struct ReceiptViewerSheet: View {
    let imageData: Data
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let uiImage = UIImage(data: imageData) {
                    ScrollView {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Text("Unable to display receipt.")
                        .foregroundStyle(ThemeTokens.textSecondary)
                }
            }
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
