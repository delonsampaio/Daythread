//
//  AddExpenseSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData
import PhotosUI

struct AddExpenseSheet: View {
    let trip: Trip
    let vm: VaultViewModel
    let editingExpense: TripExpense?  // nil = add mode, non-nil = edit mode

    @Environment(\.managedObjectContext) private var context
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var amount: String
    @State private var currencyCode: String
    @State private var category: ExpenseCategory
    @State private var date: Date
    @State private var paidByMemberID: UUID?
    @State private var splitAmongIDs: Set<UUID>   // empty = all members (implicit)
    @State private var notes: String
    @State private var receiptImageData: Data?

    // Receipt UI state — always start closed
    @State private var showReceiptSourcePicker = false
    @State private var showReceiptPhotoPicker = false
    @State private var showReceiptCamera = false
    @State private var receiptPhotoItem: PhotosPickerItem?
    @State private var showPaywall = false
    @State private var showSettlementWarning = false

    private let currencies = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "CNY"]

    private var members: [TripMember] {
        trip.membersArray.sorted { $0.displayName < $1.displayName }
    }

    /// True when splitAmongIDs represents "everyone" (the default).
    private var isSplitAmongAll: Bool { splitAmongIDs.isEmpty }

    /// The effective split set as UUIDs, resolving "implicit all" to an explicit set.
    private var currentSplitSet: Set<UUID> {
        isSplitAmongAll ? Set(members.map(\.id)) : splitAmongIDs
    }

    /// True if the trip has any explicitly flagged settlement expenses.
    private var tripHasSettlements: Bool {
        trip.expensesArray.contains(where: \.isSettlement)
    }

    /// True when editing would change any field that affects the debt calculation
    /// while settlements exist. Changing amount, split-among, payer, or currency
    /// can make already-recorded settlements inaccurate.
    private var editWillAffectSettlements: Bool {
        guard let original = editingExpense else { return false }
        let amountChanged   = (Double(amount) ?? 0) != original.amount
        let splitChanged    = currentSplitSet != Set(original.splitAmongIDs)
        let payerChanged    = paidByMemberID != original.paidByMemberID
        let currencyChanged = currencyCode != original.currencyCode
        return (amountChanged || splitChanged || payerChanged || currencyChanged) && tripHasSettlements
    }

    init(trip: Trip, vm: VaultViewModel, editingExpense: TripExpense? = nil) {
        self.trip = trip
        self.vm = vm
        self.editingExpense = editingExpense

        if let expense = editingExpense {
            _title          = State(initialValue: expense.title)
            _amount         = State(initialValue: String(format: "%.2f", expense.amount))
            _currencyCode   = State(initialValue: expense.currencyCode)
            _category       = State(initialValue: expense.category)
            _date           = State(initialValue: expense.date)
            _paidByMemberID = State(initialValue: expense.paidByMemberID)
            // Explicit-all is reconciled back to implicit-all (empty) in .onAppear,
            // once we have access to the current members list.
            _splitAmongIDs  = State(initialValue: Set(expense.splitAmongIDs))
            _notes          = State(initialValue: expense.notes)
            _receiptImageData = State(initialValue: expense.receiptImageData)
        } else {
            _title          = State(initialValue: "")
            _amount         = State(initialValue: "")
            _currencyCode   = State(initialValue: "USD")
            _category       = State(initialValue: .other)
            _date           = State(initialValue: Date())
            _paidByMemberID = State(initialValue: nil)
            _splitAmongIDs  = State(initialValue: [])
            _notes          = State(initialValue: "")
            _receiptImageData = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What was it for?", text: $title)
                    HStack {
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                        Picker("", selection: $currencyCode) {
                            ForEach(currencies, id: \.self) { Text($0).tag($0) }
                        }
                        .fixedSize()
                    }
                }

                Section {
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.systemImage).tag(cat)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                // Member-aware splitting — shown when participants are set up.
                if !members.isEmpty {
                    Section("Paid by") {
                        Picker("Paid by", selection: $paidByMemberID) {
                            // "Untracked" is removed when participants exist —
                            // a payer is required to produce correct settlements.
                            ForEach(members) { member in
                                Text(member.displayName).tag(UUID?.some(member.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Section {
                        ForEach(members) { member in
                            Toggle(member.displayName, isOn: includedBinding(for: member.id))
                        }
                    } header: {
                        Text("Split among")
                    } footer: {
                        let count = isSplitAmongAll ? members.count : splitAmongIDs.count
                        Text("Split \(count == members.count ? "evenly among all" : "among \(count)") participant\(count == 1 ? "" : "s").")
                            .font(.caption)
                    }
                }

                Section {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Receipt") {
                    if !store.isPro {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                Label("Attach Receipt", systemImage: "camera")
                                    .foregroundStyle(ThemeTokens.textMuted)
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(ThemeTokens.textMuted)
                            }
                        }
                    } else if let data = receiptImageData, let uiImage = UIImage(data: data) {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            HStack {
                                Button("Replace") { showReceiptSourcePicker = true }
                                    .font(.footnote)
                                    .foregroundStyle(ThemeTokens.accent)
                                Spacer()
                                Button("Remove", role: .destructive) { receiptImageData = nil }
                                    .font(.footnote)
                            }
                        }
                    } else {
                        Button {
                            showReceiptSourcePicker = true
                        } label: {
                            Label("Attach Receipt…", systemImage: "camera")
                                .foregroundStyle(ThemeTokens.accent)
                        }
                    }
                }
            }
            .navigationTitle(editingExpense == nil ? "Add Expense" : "Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if editWillAffectSettlements {
                            showSettlementWarning = true
                        } else {
                            save()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(
                        title.isEmpty ||
                        Double(amount) == nil ||
                        // Payer is mandatory when participants are set up.
                        (!members.isEmpty && paidByMemberID == nil)
                    )
                }
            }
            .confirmationDialog("Attach Receipt", isPresented: $showReceiptSourcePicker, titleVisibility: .visible) {
                Button("Camera") { showReceiptCamera = true }
                Button("Photo Library") { showReceiptPhotoPicker = true }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showReceiptCamera) {
                ReceiptCameraPickerView { image in
                    receiptImageData = image.jpegData(compressionQuality: 0.85)
                }
            }
            .photosPicker(isPresented: $showReceiptPhotoPicker, selection: $receiptPhotoItem, matching: .images)
            .onChange(of: receiptPhotoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        receiptImageData = data
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                ProPaywallView()
            }
            .alert("Settlements May Be Affected", isPresented: $showSettlementWarning) {
                Button("Save Anyway", role: .destructive) { save() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You've already settled some debts for this trip. Changing the amount or who splits this expense can make those settlements inaccurate. You can delete any outdated settlements from the Split Expenses view.")
            }
            .onAppear {
                if editingExpense != nil {
                    // Reconcile "explicit all" → "implicit all" (empty set) so all
                    // member toggles render as ON rather than individually checked.
                    let allMemberIDs = Set(members.map(\.id))
                    if splitAmongIDs == allMemberIDs { splitAmongIDs = [] }
                } else {
                    // New expense: default payer to first member.
                    if paidByMemberID == nil, let first = members.first {
                        paidByMemberID = first.id
                    }
                }
            }
        }
    }

    // MARK: — Helpers

    /// Binding that toggles a member's inclusion in the split.
    /// When all members are included and the user unchecks one, we switch
    /// from "implicit all" to an explicit set.
    private func includedBinding(for memberID: UUID) -> Binding<Bool> {
        Binding(
            get: {
                isSplitAmongAll || splitAmongIDs.contains(memberID)
            },
            set: { included in
                if isSplitAmongAll {
                    // Expand the implicit "all" into an explicit set, then remove.
                    splitAmongIDs = Set(members.map(\.id))
                }
                if included {
                    splitAmongIDs.insert(memberID)
                } else {
                    splitAmongIDs.remove(memberID)
                    // If back to everyone, collapse to "all" again.
                    if splitAmongIDs.count == members.count {
                        splitAmongIDs = []
                    }
                }
            }
        )
    }

    private func save() {
        // Always snapshot the explicit UUIDs of who is included at save time.
        // NEVER write an empty array — empty would retroactively include any
        // member who joins the trip later (the "Ghost Debtor" bug).
        let finalSplitAmongIDs: [UUID] = isSplitAmongAll
            ? members.map(\.id)
            : Array(splitAmongIDs)

        if let expense = editingExpense {
            expense.title           = title
            expense.amount          = Double(amount) ?? expense.amount
            expense.currencyCode    = currencyCode
            expense.category        = category
            expense.date            = date
            expense.paidByMemberID  = paidByMemberID
            expense.splitAmongIDs   = finalSplitAmongIDs
            expense.notes           = notes
            if store.isPro { expense.receiptImageData = receiptImageData }
            try? context.save()
        } else {
            let newExpense = TripExpense(context: context)
            newExpense.id              = UUID()
            newExpense.title           = title
            newExpense.amount          = Double(amount) ?? 0
            newExpense.currencyCode    = currencyCode
            newExpense.category        = category
            newExpense.date            = date
            newExpense.paidByMemberID  = paidByMemberID
            newExpense.splitAmongIDs   = finalSplitAmongIDs
            newExpense.notes           = notes
            newExpense.isSettlement    = false
            if store.isPro { newExpense.receiptImageData = receiptImageData }
            // Zone-hopping: link parent before save.
            vm.addExpense(newExpense, to: trip, context: context)
        }
        HapticManager.shared.sheetConfirm()
        dismiss()
    }
}

// MARK: — Camera picker

private struct ReceiptCameraPickerView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ReceiptCameraPickerView
        init(_ parent: ReceiptCameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
