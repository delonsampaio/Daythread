//
//  AddDocumentSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI

struct AddDocumentSheet: View {
    let trip: Trip
    let vm: VaultViewModel

    @Environment(\.modelContext) private var context
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var selectedData: Data?
    @State private var mimeType: String = "application/pdf"
    @State private var expiryDate: Date = Date()
    @State private var hasExpiry: Bool = false

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
    }

    private func save() {
        guard let data = selectedData else { return }
        vm.addDocument(title: title, data: data, mimeType: mimeType,
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
