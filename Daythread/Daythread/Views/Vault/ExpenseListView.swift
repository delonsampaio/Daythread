//
//  ExpenseListView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData

struct ExpenseListView: View {
    let trip: Trip
    let vm: VaultViewModel

    @Environment(\.managedObjectContext) private var context
    @Environment(TripStore.self) private var store
    @State private var showAdd = false
    @State private var showSplit = false
    @State private var editingExpense: TripExpense?
    @State private var pendingDelete: TripExpense?      // settlements alert
    @State private var pendingUndoDelete: PendingDelete? // undo toast
    @State private var viewingReceiptData: Data?

    /// True if the trip has any settlement expenses.
    private var tripHasSettlements: Bool {
        trip.expensesArray.contains { e in
            e.splitAmongIDs.count == 1 &&
            e.paidByMemberID != nil &&
            e.paidByMemberID != e.splitAmongIDs.first
        }
    }

    /// Uses the explicit flag set by settleDebt() — no structural heuristics.
    private func isSettlement(_ expense: TripExpense) -> Bool {
        expense.isSettlement
    }

    private func requestDelete(_ expense: TripExpense) {
        if tripHasSettlements && !isSettlement(expense) {
            // Settlements alert first — undo toast fires after confirmation.
            pendingDelete = expense
        } else {
            pendingUndoDelete = PendingDelete(
                id: expense.objectID,
                label: expense.title.isEmpty ? "Expense" : expense.title
            )
        }
    }

    private var expenses: [TripExpense] {
        trip.expensesArray
            .filter { $0.objectID != pendingUndoDelete?.id }
            .sorted { $0.date > $1.date }
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
                        Image(systemName: expense.isSettlement
                              ? "arrow.triangle.2.circlepath"
                              : expense.category.systemImage)
                            .frame(width: 28)
                            .foregroundStyle(expense.isSettlement
                                             ? ThemeTokens.textMuted
                                             : ThemeTokens.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(expense.title)
                                    .font(.system(size: 14, weight: .semibold))
                                if expense.isSettlement {
                                    Text("Settlement")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(ThemeTokens.textMuted)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(ThemeTokens.textMuted.opacity(0.12)))
                                }
                            }
                            HStack(spacing: 4) {
                                Text(expense.isSettlement ? "Settlement" : expense.category.displayName)
                                    .font(.caption)
                                    .foregroundStyle(ThemeTokens.textSecondary)
                                if let payerID = expense.paidByMemberID,
                                   let name = trip.membersArray.first(where: { $0.id == payerID })?.displayName {
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            requestDelete(expense)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            editingExpense = expense
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(ThemeTokens.accent)
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") {
                            editingExpense = expense
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            requestDelete(expense)
                        }
                    }
                }
            }

        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Skip Pro gate when the trip is shared — the invitee
                    // didn't choose to need Pro, and splitting in a shared
                    // trip requires the feature to work for all participants.
                    guard store.isPro || trip.cloudKitShareID != nil else {
                        vm.showPaywall = true; return
                    }
                    showSplit = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddExpenseSheet(trip: trip, vm: vm)
        }
        .sheet(item: $editingExpense) { expense in
            AddExpenseSheet(trip: trip, vm: vm, editingExpense: expense)
        }
        .alert("Settlements May Be Affected", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete Anyway", role: .destructive) {
                if let expense = pendingDelete {
                    pendingUndoDelete = PendingDelete(
                        id: expense.objectID,
                        label: expense.title.isEmpty ? "Expense" : expense.title
                    )
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("You've already settled some debts for this trip. Deleting this expense may make those settlements inaccurate. You can delete outdated settlements from the Split Expenses view.")
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
        .undoDelete(pending: $pendingUndoDelete) { id in
            if let expense = try? context.existingObject(with: id) as? TripExpense {
                vm.deleteExpense(expense, context: context)
            }
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
