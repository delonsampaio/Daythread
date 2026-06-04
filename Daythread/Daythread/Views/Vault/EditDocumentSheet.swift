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
    @State private var sharedWithMemberIDs: Set<String>

    private var otherMembers: [TripMember] {
        let myID = store.currentUserCloudKitID ?? ""
        return (document.trip?.membersArray ?? []).filter {
            !$0.appleUserID.isEmpty && $0.appleUserID != myID && !$0.isVirtual
        }
    }

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
        let ids = document.visibleToMemberIDs
        _sharedWithMemberIDs = State(initialValue:
            ids.isEmpty ? [] : Set(ids.split(separator: ",").map(String.init))
        )
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
                if document.trip?.cloudKitShareID != nil, isOriginator {
                    Section("Visibility") {
                        Button {
                            isShared = true; sharedWithMemberIDs = []
                        } label: {
                            HStack {
                                Label("Everyone on the trip", systemImage: "person.2")
                                Spacer()
                                if isShared { Image(systemName: "checkmark").foregroundStyle(ThemeTokens.accent) }
                            }
                        }
                        .foregroundStyle(ThemeTokens.textPrimary).buttonStyle(.plain)

                        Button {
                            isShared = false; sharedWithMemberIDs = []
                        } label: {
                            HStack {
                                Label("Only me", systemImage: "person")
                                Spacer()
                                if !isShared && sharedWithMemberIDs.isEmpty {
                                    Image(systemName: "checkmark").foregroundStyle(ThemeTokens.accent)
                                }
                            }
                        }
                        .foregroundStyle(ThemeTokens.textPrimary).buttonStyle(.plain)

                        if !otherMembers.isEmpty {
                            Button {
                                isShared = false
                                if sharedWithMemberIDs.isEmpty {
                                    sharedWithMemberIDs = Set(otherMembers.map(\.appleUserID))
                                }
                            } label: {
                                HStack {
                                    Label("Specific people", systemImage: "person.badge.plus")
                                    Spacer()
                                    if !isShared && !sharedWithMemberIDs.isEmpty {
                                        Image(systemName: "checkmark").foregroundStyle(ThemeTokens.accent)
                                    }
                                }
                            }
                            .foregroundStyle(ThemeTokens.textPrimary).buttonStyle(.plain)

                            if !isShared && !sharedWithMemberIDs.isEmpty {
                                ForEach(otherMembers) { member in
                                    let id = member.appleUserID
                                    Button {
                                        if sharedWithMemberIDs.contains(id) { sharedWithMemberIDs.remove(id) }
                                        else { sharedWithMemberIDs.insert(id) }
                                    } label: {
                                        HStack {
                                            Image(systemName: sharedWithMemberIDs.contains(id)
                                                  ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(sharedWithMemberIDs.contains(id)
                                                                 ? ThemeTokens.accent : ThemeTokens.textMuted)
                                            Text(member.displayName.isEmpty ? "Traveler" : member.displayName)
                                                .foregroundStyle(ThemeTokens.textPrimary)
                                        }
                                    }
                                    .buttonStyle(.plain).padding(.leading, 20)
                                }
                            }
                        }
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
        document.isShared = isShared
        document.visibleToMemberIDs = (!isShared && !sharedWithMemberIDs.isEmpty)
            ? sharedWithMemberIDs.sorted().joined(separator: ",")
            : ""
        if isOriginator { document.isLocked = isLocked }
        try? context.save()
        HapticManager.shared.sheetConfirm()
        dismiss()
    }
}
