//
//  DocumentGridView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData
import QuickLook

struct DocumentGridView: View {
    let trip: Trip
    let vm: VaultViewModel

    @Environment(\.managedObjectContext) private var context
    @Environment(TripStore.self) private var store

    /// True when the current device's user is the admin/owner of a shared trip,
    /// or when the trip isn't shared. Admins see all documents; participants see
    /// only documents the owner has marked as shared.
    private var currentUserIsOwner: Bool {
        guard trip.cloudKitShareID != nil,
              let myID = store.currentUserCloudKitID else { return true }
        return trip.membersArray.first { $0.appleUserID == myID }?.role == .admin
    }

    @State private var showAdd = false
    @State private var viewingDocument: TripDocument?
    @State private var editingDocument: TripDocument?
    @State private var pendingUndoDelete: PendingDelete?

    private let columns = [GridItem(.adaptive(minimum: 100))]

    /// Documents sorted with the most urgent expiry dates first (ascending),
    /// then documents without expiry ordered by creation date. Keeps the grid
    /// stable across navigations — NSSet ordering is undefined.
    private var sortedDocuments: [TripDocument] {
        trip.documentsArray
            .filter { $0.objectID != pendingUndoDelete?.id }
            .filter { currentUserIsOwner || $0.isShared }
            .sorted { a, b in
            switch (a.expiryDate, b.expiryDate) {
            case (let ea?, let eb?): return ea < eb
            case (.some, nil):       return true   // expiring docs float to top
            case (nil, .some):       return false
            case (nil, nil):         return a.addedAt < b.addedAt
            }
        }
    }

    var body: some View {
        Group {
            if sortedDocuments.isEmpty {
                ContentUnavailableView("No documents yet",
                                       systemImage: "doc.fill",
                                       description: Text("Add passports, visas, and boarding passes."))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(sortedDocuments) { doc in
                            documentTile(doc)
                        }
                    }
                    .padding()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddDocumentSheet(trip: trip, vm: vm)
        }
        .sheet(item: $viewingDocument) { doc in
            DocumentViewerSheet(document: doc)
        }
        .sheet(item: $editingDocument) { doc in
            EditDocumentSheet(document: doc)
        }
        .undoDelete(pending: $pendingUndoDelete) { id in
            if let doc = try? context.existingObject(with: id) as? TripDocument {
                vm.deleteDocument(doc, context: context)
            }
        }
    }

    @ViewBuilder
    private func documentTile(_ doc: TripDocument) -> some View {
        Button {
            viewingDocument = doc
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(ThemeTokens.backgroundCard)
                        .frame(height: 90)

                    // Thumbnail for images, icon for PDFs
                    if doc.mimeType != "application/pdf",
                       let data = doc.documentData,
                       let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Image(systemName: doc.mimeType == "application/pdf" ? "doc.fill" : "photo.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(ThemeTokens.accent)
                    }

                    // Expiry badge
                    if let expiry = doc.expiryDate {
                        VStack {
                            HStack {
                                Spacer()
                                expiryBadge(expiry)
                            }
                            Spacer()
                        }
                        .padding(6)
                    }
                }
                Text(doc.title)
                    .font(.caption.bold())
                    .foregroundStyle(ThemeTokens.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button("Edit Details", systemImage: "pencil") {
                editingDocument = doc
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                pendingUndoDelete = PendingDelete(
                    id: doc.objectID,
                    label: doc.title.isEmpty ? "Document" : doc.title
                )
            }
        }
    }

    /// Expiry badge thresholds:
    ///   Expired / < 30 days  → red   (actionable danger)
    ///   30 – 89 days         → amber (advance warning — passport 6-month entry rules)
    ///   90+ days             → hidden
    @ViewBuilder
    private func expiryBadge(_ date: Date) -> some View {
        let daysUntil = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
        let color: Color = daysUntil < 0 ? .red
                         : daysUntil < 30 ? .red
                         : daysUntil < 90 ? ThemeTokens.warningAmber
                         : .clear
        if color != .clear {
            Text(daysUntil < 0 ? "Expired" : "\(daysUntil)d")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(color))
        }
    }
}

// MARK: — Document viewer

/// Writes document data to a UUID-named temp file in .task (not in init or
/// the render cycle) and explicitly removes it on .onDisappear to prevent
/// orphaned file accumulation in the temporary directory.
private struct DocumentViewerSheet: View {
    let document: TripDocument
    @Environment(\.dismiss) private var dismiss
    @State private var tempURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if document.documentData == nil {
                    ContentUnavailableView("No file data", systemImage: "doc.badge.exclamationmark")
                } else if let url = tempURL {
                    QuickLookPreviewView(url: url)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                if let url = tempURL {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            // Write to a UUID-named temp file so parallel viewers don't collide
            // and the safe title sanitisation code is unnecessary.
            .task {
                guard let data = document.documentData else { return }
                let ext = document.mimeType == "application/pdf" ? "pdf" : "jpg"
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(ext)
                try? data.write(to: url)
                tempURL = url
            }
            // Explicit cleanup — iOS clears the tmp dir eventually but only under
            // disk pressure. Removing eagerly keeps the app's footprint clean.
            .onDisappear {
                if let url = tempURL {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }
}

// MARK: — QuickLook wrapper

/// Takes a pre-written URL rather than raw Data so the file lifecycle
/// (write + delete) is owned by the enclosing DocumentViewerSheet.
private struct QuickLookPreviewView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url; super.init() }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
