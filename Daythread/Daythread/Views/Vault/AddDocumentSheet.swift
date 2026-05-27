//
//  AddDocumentSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AddDocumentSheet: View {
    let trip: Trip
    let vm: VaultViewModel

    @Environment(\.modelContext) private var context
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var isImporting: Bool = false
    @State private var selectedData: Data?
    @State private var mimeType: String = "application/pdf"
    @State private var expiryDate: Date = Date()
    @State private var hasExpiry: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Document title (e.g. Passport — Delon)", text: $title)
                }
                Section("File") {
                    Button("Choose File (PDF or Image)") { isImporting = true }
                        .foregroundStyle(ThemeTokens.accent)
                    if selectedData != nil {
                        Label("File selected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(ThemeTokens.successGreen)
                    }
                }
                Section {
                    Toggle("Has expiry date", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Expiry", selection: $expiryDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Add Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.isEmpty || selectedData == nil)
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    _ = url.startAccessingSecurityScopedResource()
                    selectedData = try? Data(contentsOf: url)
                    mimeType = url.pathExtension == "pdf" ? "application/pdf" : "image/jpeg"
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }
    }

    private func save() {
        guard let data = selectedData else { return }
        vm.addDocument(title: title, data: data, mimeType: mimeType,
                       to: trip, isPro: store.isPro, context: context)
        HapticManager.shared.sheetConfirm()
        dismiss()
    }
}
