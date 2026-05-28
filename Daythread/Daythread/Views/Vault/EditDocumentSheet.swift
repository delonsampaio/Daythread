//
//  EditDocumentSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/28/26.
//
//  Lightweight edit sheet for a TripDocument — title and expiry date only.
//  documentData is intentionally not touched here; re-uploading the file
//  would require the user to delete and re-add the document.
//

import SwiftUI
import SwiftData

struct EditDocumentSheet: View {
    let document: TripDocument

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var hasExpiry: Bool
    @State private var expiryDate: Date

    init(document: TripDocument) {
        self.document = document
        _title      = State(initialValue: document.title)
        _hasExpiry  = State(initialValue: document.expiryDate != nil)
        _expiryDate = State(initialValue: document.expiryDate ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Document title", text: $title)
                }
                Section {
                    Toggle("Has expiry date", isOn: $hasExpiry.animation())
                    if hasExpiry {
                        DatePicker("Expiry", selection: $expiryDate, displayedComponents: .date)
                    }
                } footer: {
                    Text("Set an expiry date for passports, visas, and insurance cards to get advance warnings on the document tile.")
                        .font(.caption)
                }
            }
            .navigationTitle("Edit Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        document.title      = title.trimmingCharacters(in: .whitespaces)
        document.expiryDate = hasExpiry ? expiryDate : nil
        try? context.save()
        HapticManager.shared.sheetConfirm()
        dismiss()
    }
}
