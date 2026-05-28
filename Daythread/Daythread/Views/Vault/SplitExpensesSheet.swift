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
//  without a separate settlements table.

import SwiftUI
import SwiftData

struct SplitExpensesSheet: View {
    let trip: Trip
    let vm: VaultViewModel

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var newName: String = ""
    @FocusState private var nameFieldFocused: Bool
    @State private var pendingSettlement: Settlement? = nil
    @State private var settleAmountText: String = ""

    private var members: [TripMember] {
        (trip.members ?? []).sorted { $0.displayName < $1.displayName }
    }
    private var expenses: [TripExpense] { trip.expenses ?? [] }
    private var settlements: [Settlement] { computeSettlements() }

    var body: some View {
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
            .alert("Settle Debt", isPresented: Binding(
                get: { pendingSettlement != nil },
                set: { if !$0 { pendingSettlement = nil } }
            ), presenting: pendingSettlement) { s in
                TextField("Amount", text: $settleAmountText)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { pendingSettlement = nil }
                Button("Settle \(s.currency)") {
                    guard let amount = Double(settleAmountText), amount > 0.005 else { return }
                    confirmSettle(s, amount: amount)
                }
            } message: { s in
                Text("\(s.debtorName) owes \(s.creditorName) \(String(format: "%.2f %@", s.amount, s.currency)). Edit the amount for a partial payment.")
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
                Text("Real co-editors appear automatically when they join the trip.")
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.textMuted)
            }
        }
    }

    // MARK: — Settlements section

    private var settlementsSection: some View {
        Section {
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

    // MARK: — Debt minimisation

    struct Settlement: Identifiable {
        let id = UUID()
        let debtorID: UUID
        let creditorID: UUID
        let debtorName: String
        let creditorName: String
        let amount: Double
        let currency: String
    }

    private func computeSettlements() -> [Settlement] {
        guard members.count >= 2, !expenses.isEmpty else { return [] }

        let memberIDs = Set(members.map(\.id))
        let currencies = Set(expenses.map(\.currencyCode))
        let nameFor: (UUID) -> String = { id in
            members.first { $0.id == id }?.displayName ?? "?"
        }

        return currencies.flatMap { currency -> [Settlement] in
            var balance: [UUID: Double] = [:]
            for m in members { balance[m.id] = 0 }

            for expense in expenses where expense.currencyCode == currency {
                guard let payer = expense.paidByMemberID,
                      memberIDs.contains(payer) else { continue }

                // splitAmongIDs is always an explicit snapshot saved at creation time.
                // We never fall back to "all members" — that would cause the Ghost
                // Debtor bug when new members join after the expense was logged.
                let participants = expense.splitAmongIDs.filter { memberIDs.contains($0) }
                guard !participants.isEmpty else { continue }
                let share = expense.amount / Double(participants.count)

                balance[payer, default: 0] += expense.amount
                for p in participants {
                    balance[p, default: 0] -= share
                }
            }

            // Greedy minimisation: largest creditor vs largest debtor.
            var creditors = balance.filter { $0.value >  0.005 }
                .map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
            var debtors   = balance.filter { $0.value < -0.005 }
                .map { ($0.key, -$0.value) }.sorted { $0.1 > $1.1 }

            var result: [Settlement] = []
            var ci = 0, di = 0

            while ci < creditors.count && di < debtors.count {
                let payment = min(creditors[ci].1, debtors[di].1)
                if payment > 0.005 {
                    result.append(Settlement(
                        debtorID:    debtors[di].0,
                        creditorID:  creditors[ci].0,
                        debtorName:  nameFor(debtors[di].0),
                        creditorName: nameFor(creditors[ci].0),
                        amount:   (payment * 100).rounded() / 100,
                        currency: currency
                    ))
                }
                creditors[ci].1 -= payment
                debtors[di].1   -= payment
                if creditors[ci].1 < 0.005 { ci += 1 }
                if debtors[di].1   < 0.005 { di += 1 }
            }
            return result
        }
    }
}

// MARK: — Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
