//
//  AddDocumentSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import PhotosUI

struct AddDocumentSheet: View {
    let trip: Trip
    let vm: VaultViewModel

    @Environment(\.managedObjectContext) private var context
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var selectedData: Data?
    @State private var mimeType: String = "application/pdf"
    @State private var expiryDate: Date = Date()
    @State private var hasExpiry: Bool = false
    @State private var isShared: Bool = false
    @State private var isLocked: Bool = true
    /// IDs of specific members (besides the originator) who can see this doc.
    @State private var sharedWithMemberIDs: Set<String> = []

    private var otherMembers: [TripMember] {
        let myID = store.currentUserCloudKitID ?? ""
        return (trip.membersArray).filter { !$0.appleUserID.isEmpty && $0.appleUserID != myID && !$0.isVirtual }
    }

    @State private var showSourcePicker = false
    @State private var showFilePicker = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var photoPickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Document title (e.g. Passport — Delon)", text: $title)
                }
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
                Section("File") {
                    Button {
                        showSourcePicker = true
                    } label: {
                        if selectedData != nil {
                            Label("File selected — tap to replace", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(ThemeTokens.successGreen)
                        } else {
                            Label("Choose File…", systemImage: "plus.circle")
                                .foregroundStyle(ThemeTokens.accent)
                        }
                    }
                }
                Section {
                    Toggle("Has expiry date", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Expiry", selection: $expiryDate, displayedComponents: .date)
                    }
                }
                if trip.cloudKitShareID != nil {
                    Section("Visibility") {
                        Button {
                            isShared = true
                            sharedWithMemberIDs = []
                        } label: {
                            HStack {
                                Label("Everyone on the trip", systemImage: "person.2")
                                Spacer()
                                if isShared { Image(systemName: "checkmark").foregroundStyle(ThemeTokens.accent) }
                            }
                        }
                        .foregroundStyle(ThemeTokens.textPrimary)
                        .buttonStyle(.plain)

                        Button {
                            isShared = false
                            sharedWithMemberIDs = []
                        } label: {
                            HStack {
                                Label("Only me", systemImage: "person")
                                Spacer()
                                if !isShared && sharedWithMemberIDs.isEmpty {
                                    Image(systemName: "checkmark").foregroundStyle(ThemeTokens.accent)
                                }
                            }
                        }
                        .foregroundStyle(ThemeTokens.textPrimary)
                        .buttonStyle(.plain)

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
                            .foregroundStyle(ThemeTokens.textPrimary)
                            .buttonStyle(.plain)

                            if !isShared && !sharedWithMemberIDs.isEmpty {
                                ForEach(otherMembers) { member in
                                    let id = member.appleUserID
                                    Button {
                                        if sharedWithMemberIDs.contains(id) {
                                            sharedWithMemberIDs.remove(id)
                                        } else {
                                            sharedWithMemberIDs.insert(id)
                                        }
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
                                    .buttonStyle(.plain)
                                    .padding(.leading, 20)
                                }
                            }
                        }
                    }
                }
                Section {
                    Toggle("Lock document", isOn: $isLocked)
                } footer: {
                    Text(isLocked
                        ? "Only you can edit this document's title and expiry date."
                        : "Anyone on the trip can edit this document's details.")
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
            .confirmationDialog("Choose Source", isPresented: $showSourcePicker, titleVisibility: .visible) {
                Button("Camera") { showCamera = true }
                Button("Photo Library") { showPhotoPicker = true }
                Button("Files (PDF or Image)") { showFilePicker = true }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showCamera) {
                CameraPickerView { image in
                    selectedData = image.jpegData(compressionQuality: 0.85)
                    mimeType = "image/jpeg"
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItem, matching: .images)
            .onChange(of: photoPickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        selectedData = data
                        mimeType = "image/jpeg"
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    _ = url.startAccessingSecurityScopedResource()
                    selectedData = try? Data(contentsOf: url)
                    mimeType = url.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg"
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }
        .presentationSizing(.page)
    }

    private func save() {
        guard let data = selectedData else { return }
        let memberIDs = (!isShared && !sharedWithMemberIDs.isEmpty)
            ? sharedWithMemberIDs.sorted().joined(separator: ",")
            : ""
        vm.addDocument(title: title, data: data, mimeType: mimeType,
                       notes: notes,
                       isShared: isShared,
                       visibleToMemberIDs: memberIDs,
                       isLocked: isLocked,
                       addedByAppleUserID: store.currentUserCloudKitID ?? "",
                       to: trip, isPro: store.isPro, context: context)
        HapticManager.shared.sheetConfirm()
        dismiss()
    }
}

// MARK: — Camera picker

private struct CameraPickerView: UIViewControllerRepresentable {
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
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

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
