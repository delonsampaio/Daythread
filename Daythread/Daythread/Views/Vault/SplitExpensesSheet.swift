//
//  SplitExpensesSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/28/26.
//
//  Shows who owes whom after splitting expenses among trip members.
//  Members are TripMember instances — virtual (isVirtual = true, no Apple ID)
//  for manually-added participants, or real for CloudKit co-editors.
//
//  "Mark Settled" creates a new TripExpense so the algorithm self-corrects
//  without a separate settlements table. Debt computation is fully delegated
//  to ExpenseSplitter so the UI is always in sync with the tested engine.

import SwiftUI
import CoreData

struct SplitExpensesSheet: View {
    @ObservedObject var trip: Trip
    let vm: VaultViewModel

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var newName: String = ""
    @FocusState private var nameFieldFocused: Bool
    @State private var pendingSettlement: Settlement? = nil
    @State private var settleAmountText: String = ""
    @State private var showAssignPayers = false

    private var members: [TripMember] {
        trip.membersArray.sorted { $0.displayName < $1.displayName }
    }
    private var expenses: [TripExpense] { trip.expensesArray }
    private var settlements: [Settlement] { computeSettlements() }

    private var untrackedExpenses: [TripExpense] {
        expenses.filter { $0.paidByMemberID == nil && !$0.isSettlement }
    }

    private var hasPriorSettlements: Bool {
        expenses.contains(where: \.isSettlement)
    }

    var body: some View {
        LiveContent(isDead: !trip.isAlive) {
        NavigationStack {
            List {
                membersSection
                if members.count >= 2 {
                    settlementsSection
                } else {
                    Section {
                        Label("Add at least 2 participants to split expenses.",
                              systemImage: "person.2")
                            .font(.subheadline)
                            .foregroundStyle(ThemeTokens.textSecondary)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Split Expenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            // Partial settlement — pre-filled with full debt, user can edit.
            // Overpayments are intentionally allowed: the ledger engine naturally
            // inverts the balance, so if Alice over-settles by $5, the ledger
            // shows Bob owes Alice $5. No clamping needed.
            .alert("Settle Debt", isPresented: Binding(
                get: { pendingSettlement != nil },
                set: { if !$0 { pendingSettlement = nil } }
            ), presenting: pendingSettlement) { s in
                TextField("Amount", text: $settleAmountText)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { pendingSettlement = nil }
                Button("Settle \(s.currency)") {
                    guard let raw = Double(settleAmountText), raw > 0.005 else { return }
                    confirmSettle(s, amount: raw)
                }
            } message: { s in
                Text("\(s.debtorName) owes \(s.creditorName) \(String(format: "%.2f %@", s.amount, s.currency)). Edit the amount for a partial payment.")
            }
            .sheet(isPresented: $showAssignPayers) {
                AssignPayersSheet(untrackedExpenses: untrackedExpenses, members: members,
                                  hasPriorSettlements: hasPriorSettlements)
            }
        }
        }
    }

    // MARK: — Members section

    private var membersSection: some View {
        Section {
            ForEach(members) { member in
                HStack {
                    Text(member.displayName)
                    Spacer()
                    if !member.isVirtual {
                        // Real co-editor — managed via GroupSync
                        Text("Co-editor")
                            .font(.caption)
                            .foregroundStyle(ThemeTokens.textMuted)
                    }
                }
            }
            .onDelete { indexSet in
                // indexSet is relative to `members` (the ForEach source).
                // Look up in `members` first, then guard isVirtual — do NOT
                // look up in a filtered array with a mismatched index.
                indexSet
                    .compactMap { members[safe: $0] }
                    .filter(\.isVirtual)
                    .forEach { vm.removeMember($0, context: context) }
            }

            HStack {
                TextField("Add participant…", text: $newName)
                    .focused($nameFieldFocused)
                    .onSubmit { addParticipant() }
                if !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: addParticipant) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(ThemeTokens.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Participants")
        } footer: {
            if members.count < 2 {
                Text("Invited group members will appear here automatically.")
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.textMuted)
            }
        }
    }

    // MARK: — Settlements section

    private var settlementsSection: some View {
        Section {
            // Actionable warning — tapping opens AssignPayersSheet so the user
            // can quickly assign a payer to each untracked expense.
            if !untrackedExpenses.isEmpty {
                Button {
                    showAssignPayers = true
                } label: {
                    HStack {
                        Label(
                            "\(untrackedExpenses.count) expense\(untrackedExpenses.count == 1 ? "" : "s") \(untrackedExpenses.count == 1 ? "has" : "have") no payer — tap to assign.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.orange.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.orange.opacity(0.08))
            }
            if expenses.isEmpty {
                Text("Add expenses to see who owes whom.")
                    .font(.subheadline)
                    .foregroundStyle(ThemeTokens.textSecondary)
            } else if settlements.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Everyone is even!")
                        .foregroundStyle(ThemeTokens.textPrimary)
                }
            } else {
                ForEach(settlements) { s in
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 0) {
                                Text(s.debtorName)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(" owes ")
                                    .font(.system(size: 14))
                                    .foregroundStyle(ThemeTokens.textSecondary)
                                Text(s.creditorName)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            Text(String(format: "%.2f %@", s.amount, s.currency))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(ThemeTokens.accent)
                        }
                        Spacer()
                        Button("Settle") {
                            pendingSettlement = s
                            settleAmountText = String(format: "%.2f", s.amount)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(ThemeTokens.accent))
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Settlements")
        } footer: {
            if !settlements.isEmpty {
                Text("Tap Settle to record a payment. The debt zeroes automatically.")
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.textMuted)
            }
        }
    }

    // MARK: — Actions

    private func addParticipant() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              !members.map(\.displayName).contains(name) else { return }
        vm.addVirtualMember(name: name, to: trip, context: context)
        newName = ""
    }

    /// Called after the partial-settlement alert is confirmed.
    /// splitAmongIDs is hardcoded to [creditorID] — the loophole guard.
    private func confirmSettle(_ s: Settlement, amount: Double) {
        guard let debtor   = members.first(where: { $0.id == s.debtorID }),
              let creditor = members.first(where: { $0.id == s.creditorID }) else { return }
        vm.settleDebt(debtor: debtor, creditor: creditor,
                      amount: amount, currencyCode: s.currency,
                      trip: trip, context: context)
        HapticManager.shared.sheetConfirm()
        pendingSettlement = nil
    }

    // MARK: — Debt minimisation (delegated to ExpenseSplitter engine)

    struct Settlement: Identifiable {
        let id = UUID()
        let debtorID: UUID
        let creditorID: UUID
        let debtorName: String
        let creditorName: String
        let amount: Double
        let currency: String
    }

    /// Maps TripExpense (Core Data) → SplitExpense (engine input),
    /// calls the tested ExpenseSplitter engine, then maps Debt → Settlement for the view.
    /// Untracked expenses (no payer) and participants who left the trip are silently
    /// skipped — the banner above handles UX communication for untracked expenses.
    private func computeSettlements() -> [Settlement] {
        guard members.count >= 2, !expenses.isEmpty else { return [] }

        let memberIDs = Set(members.map(\.id))
        let nameFor: (UUID) -> String = { id in
            members.first { $0.id == id }?.displayName ?? "?"
        }

        // Map Core Data models → engine's pure value types.
        let splitExpenses: [SplitExpense] = expenses.compactMap { expense in
            guard let payer = expense.paidByMemberID,
                  memberIDs.contains(payer) else { return nil }
            let participants = expense.splitAmongIDs.filter { memberIDs.contains($0) }
            guard !participants.isEmpty else { return nil }

            // If members have left the trip, scale the amount proportionally so
            // remaining participants keep their original per-person share rather than
            // having the departed members' shares silently redistributed among them.
            // e.g. $90 split 3 ways: if one member leaves, pass $60 (not $90) so
            // the two remaining members each owe $30, not $45.
            let originalCount = expense.splitAmongIDs.count
            let scaledAmount = originalCount > 0
                ? expense.amount / Double(originalCount) * Double(participants.count)
                : expense.amount

            return SplitExpense(
                amount: scaledAmount,
                currency: expense.currencyCode,
                paidBy: payer,
                splitAmong: participants
            )
        }

        // Engine returns the minimized debt set; map UUIDs → display names for the view.
        // Filter after rounding: sub-cent balances (e.g. 0.004) round to 0.00 and
        // must be dropped so settled debts don't linger as zero-amount rows.
        return ExpenseSplitter.minimize(expenses: splitExpenses, members: members.compactMap(\.id))
            .compactMap { debt -> Settlement? in
                let rounded = (debt.amount * 100).rounded() / 100
                guard rounded > 0 else { return nil }
                return Settlement(
                    debtorID:     debt.from,
                    creditorID:   debt.to,
                    debtorName:   nameFor(debt.from),
                    creditorName: nameFor(debt.to),
                    amount:   rounded,
                    currency: debt.currency
                )
            }
    }
}

// MARK: — Assign Payers sheet

/// Presents the list of expenses that have no payer assigned.
/// Mutates TripExpense.paidByMemberID directly (Core Data tracks pending changes),
/// then saves on Done.
private struct AssignPayersSheet: View {
    let untrackedExpenses: [TripExpense]
    let members: [TripMember]
    let hasPriorSettlements: Bool

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showSettlementWarning = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(untrackedExpenses) { expense in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(expense.title.isEmpty ? "Untitled expense" : expense.title)
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Text(String(format: "%.2f %@", expense.amount, expense.currencyCode))
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(ThemeTokens.textSecondary)
                            }
                            Picker("Paid by", selection: Binding(
                                get: { expense.paidByMemberID },
                                set: { expense.paidByMemberID = $0 }
                            )) {
                                Text("Unassigned").tag(UUID?.none)
                                ForEach(members) { member in
                                    Text(member.displayName).tag(member.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .font(.subheadline)
                        }
                        .padding(.vertical, 2)
                    }
                } footer: {
                    Text("Assigning a payer includes the expense in the debt calculation.")
                        .font(.caption)
                }
            }
            .navigationTitle("Assign Payers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if hasPriorSettlements {
                            showSettlementWarning = true
                        } else {
                            try? context.save()
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Settlements May Be Affected", isPresented: $showSettlementWarning) {
                Button("Save Anyway", role: .destructive) {
                    try? context.save()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You've already settled some debts for this trip. Assigning payers to older expenses will update your group's balances, which may affect past settlements.")
            }
        }
    }
}

// MARK: — Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
