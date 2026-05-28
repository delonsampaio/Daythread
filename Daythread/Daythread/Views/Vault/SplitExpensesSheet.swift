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
                // Only allow deleting virtual members from this sheet.
                let virtualMembers = members.filter(\.isVirtual)
                indexSet
                    .compactMap { virtualMembers[safe: $0] }
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
                            settleDebt(s)
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

    private func settleDebt(_ s: Settlement) {
        guard let debtor   = members.first(where: { $0.id == s.debtorID }),
              let creditor = members.first(where: { $0.id == s.creditorID }) else { return }
        vm.settleDebt(debtor: debtor, creditor: creditor,
                      amount: s.amount, currencyCode: s.currency,
                      trip: trip, context: context)
        HapticManager.shared.sheetConfirm()
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

                // Resolve who this expense is split among.
                // Empty splitAmongIDs means "everyone".
                let participants: [UUID] = expense.splitAmongIDs.isEmpty
                    ? members.map(\.id)
                    : expense.splitAmongIDs.filter { memberIDs.contains($0) }

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
