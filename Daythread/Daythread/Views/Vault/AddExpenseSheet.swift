//
//  AddExpenseSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import SwiftData
import PhotosUI

struct AddExpenseSheet: View {
    let trip: Trip
    let vm: VaultViewModel

    @Environment(\.modelContext) private var context
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var amount: String = ""
    @State private var currencyCode: String = "USD"
    @State private var category: ExpenseCategory = .other
    @State private var date: Date = Date()
    @State private var notes: String = ""

    // Receipt
    @State private var receiptImageData: Data?
    @State private var showReceiptSourcePicker = false
    @State private var showReceiptPhotoPicker = false
    @State private var showReceiptCamera = false
    @State private var receiptPhotoItem: PhotosPickerItem?
    @State private var showPaywall = false

    private let currencies = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "CNY"]

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
                                Label("Attach Receipt", systemImage: "camera.badge.plus")
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
                            Label("Attach Receipt…", systemImage: "camera.badge.plus")
                                .foregroundStyle(ThemeTokens.accent)
                        }
                    }
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.isEmpty || Double(amount) == nil)
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
        }
    }

    private func save() {
        let expense = TripExpense(
            title: title,
            amount: Double(amount) ?? 0,
            currencyCode: currencyCode,
            category: category,
            date: date,
            notes: notes,
            receiptImageData: store.isPro ? receiptImageData : nil
        )
        vm.addExpense(expense, to: trip, context: context)
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
