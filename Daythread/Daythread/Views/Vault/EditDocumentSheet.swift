//
//  EditDocumentSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/28/26.
//
//  Lightweight edit sheet for a TripDocument — title, expiry, sharing, and lock.
//  documentData is intentionally not touched here; re-uploading the file
//  would require the user to delete and re-add the document.
//

import SwiftUI
import CoreData

struct EditDocumentSheet: View {
    let document: TripDocument

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(TripStore.self) private var store

    @State private var title: String
    @State private var notes: String
    @State private var hasExpiry: Bool
    @State private var expiryDate: Date
    @State private var isShared: Bool
    @State private var isLocked: Bool

    /// True when the current user is the person who originally added this document.
    /// Pre-tracking documents (empty addedByAppleUserID) are owned by whoever is
    /// looking at them from the private store (trip owner's device).
    private var isOriginator: Bool {
        let myID = store.currentUserCloudKitID ?? ""
        if document.addedByAppleUserID.isEmpty {
            return document.trip?.objectID.persistentStore?.url?.lastPathComponent != "shared.sqlite"
        }
        return !myID.isEmpty && document.addedByAppleUserID == myID
    }

    /// Whether the current user can edit title/expiry: always yes for the
    /// originator, and yes for others only when the document is not locked.
    private var canEditDetails: Bool { isOriginator || !document.isLocked }

    init(document: TripDocument) {
        self.document = document
        _title      = State(initialValue: document.title)
        _notes      = State(initialValue: document.notes)
        _hasExpiry  = State(initialValue: document.expiryDate != nil)
        _expiryDate = State(initialValue: document.expiryDate ?? .now)
        _isShared   = State(initialValue: document.isShared)
        _isLocked   = State(initialValue: document.isLocked)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Document title", text: $title)
                        .disabled(!canEditDetails)
                }
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                        .disabled(!canEditDetails)
                }
                Section {
                    Toggle("Has expiry date", isOn: $hasExpiry.animation())
                        .disabled(!canEditDetails)
                    if hasExpiry {
                        DatePicker("Expiry", selection: $expiryDate, displayedComponents: .date)
                            .disabled(!canEditDetails)
                    }
                } footer: {
                    if !canEditDetails {
                        Text("This document is locked. Only the person who added it can make changes.")
                            .font(.caption)
                    } else {
                        Text("Set an expiry date for passports, visas, and insurance cards to get advance warnings on the document tile.")
                            .font(.caption)
                    }
                }
                Section {
                    Toggle("Share with trip members", isOn: $isShared)
                        .disabled(!isOriginator)
                } footer: {
                    if !isOriginator {
                        Text("Only the person who added this document can change its sharing setting.")
                    } else if document.trip?.cloudKitShareID != nil {
                        Text(isShared
                            ? "Co-editors can view this document."
                            : "Only you can see this document. Toggle on to share it.")
                    } else {
                        Text("If you share this trip later, co-editors will be able to see this document.")
                    }
                }
                if isOriginator {
                    Section {
                        Toggle("Lock document", isOn: $isLocked)
                    } footer: {
                        Text(isLocked
                            ? "Only you can edit this document's title and expiry date."
                            : "Anyone on the trip can edit this document's details.")
                    }
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
        document.notes      = notes
        document.expiryDate = hasExpiry ? expiryDate : nil
        document.isShared   = isShared
        if isOriginator { document.isLocked = isLocked }
        try? context.save()
        HapticManager.shared.sheetConfirm()
        dismiss()
    }
}
