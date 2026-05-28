//
//  SplitExpensesSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/28/26.
//
//  Shows who owes whom after splitting all expenses evenly among participants.
//  Participants are plain display-name strings stored on the Trip model —
//  no CloudKit account required.

import SwiftUI
import SwiftData

struct SplitExpensesSheet: View {
    let trip: Trip

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var newName: String = ""
    @FocusState private var nameFieldFocused: Bool

    private var participants: [String] { trip.participantNames }
    private var expenses: [TripExpense]  { trip.expenses ?? [] }
    private var settlements: [Settlement] { computeSettlements() }

    var body: some View {
        NavigationStack {
            List {
                participantsSection
                if participants.count >= 2 && !expenses.isEmpty {
                    settlementsSection
                } else if participants.count >= 2 {
                    Section("Settlements") {
                        Text("Add expenses to see who owes whom.")
                            .font(.subheadline)
                            .foregroundStyle(ThemeTokens.textSecondary)
                    }
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

    // MARK: — Participants section

    private var participantsSection: some View {
        Section("Participants") {
            ForEach(participants, id: \.self) { name in
                Text(name)
            }
            .onDelete { indexSet in
                var names = trip.participantNames
                names.remove(atOffsets: indexSet)
                trip.participantNames = names
                try? context.save()
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
        }
    }

    // MARK: — Settlements section

    private var settlementsSection: some View {
        Section {
            if settlements.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Everyone is even!")
                        .foregroundStyle(ThemeTokens.textPrimary)
                }
            } else {
                ForEach(settlements) { settlement in
                    HStack(spacing: 0) {
                        Text(settlement.from)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ThemeTokens.textPrimary)
                        Text(" owes ")
                            .font(.system(size: 14))
                            .foregroundStyle(ThemeTokens.textSecondary)
                        Text(settlement.to)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ThemeTokens.textPrimary)
                        Spacer()
                        Text(String(format: "%.2f %@", settlement.amount, settlement.currency))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(ThemeTokens.accent)
                    }
                }
            }
        } header: {
            Text("Settlements")
        } footer: {
            Text("Expenses are split evenly among all \(participants.count) participants.")
                .font(.caption)
                .foregroundStyle(ThemeTokens.textMuted)
        }
    }

    // MARK: — Actions

    private func addParticipant() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !participants.contains(name) else { return }
        trip.participantNames.append(name)
        try? context.save()
        newName = ""
    }

    // MARK: — Debt minimisation

    private struct Settlement: Identifiable {
        let id = UUID()
        let from: String
        let to: String
        let amount: Double
        let currency: String
    }

    private func computeSettlements() -> [Settlement] {
        guard participants.count >= 2, !expenses.isEmpty else { return [] }

        let currencies = Set(expenses.map(\.currencyCode))
        return currencies.flatMap { currency -> [Settlement] in
            var balance: [String: Double] = [:]
            for p in participants { balance[p] = 0 }

            for expense in expenses where expense.currencyCode == currency {
                // Use paidBy if it's a known participant, otherwise default to first.
                let payer = participants.contains(expense.paidBy) ? expense.paidBy : participants[0]
                let share = expense.amount / Double(participants.count)
                balance[payer, default: 0] += expense.amount
                for p in participants {
                    balance[p, default: 0] -= share
                }
            }

            // Greedy debt minimisation (same algorithm as ExpenseSplitter engine).
            var creditors = balance.filter { $0.value >  0.005 }.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
            var debtors   = balance.filter { $0.value < -0.005 }.map { ($0.key, -$0.value) }.sorted { $0.1 > $1.1 }

            var result: [Settlement] = []
            var ci = 0, di = 0

            while ci < creditors.count && di < debtors.count {
                let payment = min(creditors[ci].1, debtors[di].1)
                if payment > 0.005 {
                    result.append(Settlement(
                        from: debtors[di].0,
                        to:   creditors[ci].0,
                        amount: (payment * 100).rounded() / 100,
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
