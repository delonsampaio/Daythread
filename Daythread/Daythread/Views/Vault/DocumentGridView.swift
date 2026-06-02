//
//  DocumentGridView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData
import QuickLook

// MARK: — Sort + view-mode types

private enum DocumentSortOrder: String, CaseIterable {
    case expiryAsc   = "Expiry (soonest first)"
    case nameAsc     = "Name (A–Z)"
    case addedNewest = "Date added (newest)"
    case addedOldest = "Date added (oldest)"
}

private enum DocumentViewMode: String {
    case grid, list
}

// MARK: — DocumentGridView

struct DocumentGridView: View {
    @ObservedObject var trip: Trip
    let vm: VaultViewModel

    @Environment(\.managedObjectContext) private var context
    @Environment(TripStore.self) private var store

    /// Persisted so the choice survives navigation and app restarts.
    @AppStorage("daythread.documentViewMode") private var viewModeRaw: String = DocumentViewMode.grid.rawValue
    @State private var sortOrder: DocumentSortOrder = .expiryAsc

    private var viewMode: DocumentViewMode { DocumentViewMode(rawValue: viewModeRaw) ?? .grid }

    /// The current device's CloudKit user ID, if known.
    private var myID: String? { store.currentUserCloudKitID }

    /// True when the trip lives in the owner's private store (not shared.sqlite).
    private var isOwnerDevice: Bool {
        trip.objectID.persistentStore?.url?.lastPathComponent != "shared.sqlite"
    }

    /// True when the current user is the originator of this document.
    private func isOriginator(_ doc: TripDocument) -> Bool {
        if doc.addedByAppleUserID.isEmpty { return isOwnerDevice }
        let id = myID ?? ""
        return !id.isEmpty && doc.addedByAppleUserID == id
    }

    private func isVisible(_ doc: TripDocument) -> Bool {
        guard trip.cloudKitShareID != nil else { return true }
        guard let id = myID else { return true }
        if doc.addedByAppleUserID.isEmpty { return isOwnerDevice || doc.isShared }
        return doc.isShared || doc.addedByAppleUserID == id
    }

    @State private var showAdd = false
    @State private var viewingDocument: TripDocument?
    @State private var editingDocument: TripDocument?
    @State private var pendingUndoDelete: PendingDelete?
    /// Bumped on CloudKit remote-change merges so documentsArray is re-read.
    @State private var remoteChangeToken = 0

    private let gridColumns = [GridItem(.adaptive(minimum: 100))]

    private var sortedDocuments: [TripDocument] {
        trip.documentsArray
            .filter { $0.objectID != pendingUndoDelete?.id }
            .filter { isVisible($0) }
            .sorted { a, b in
                switch sortOrder {
                case .expiryAsc:
                    switch (a.expiryDate, b.expiryDate) {
                    case (let ea?, let eb?): return ea < eb
                    case (.some, nil):       return true
                    case (nil, .some):       return false
                    case (nil, nil):         return a.addedAt < b.addedAt
                    }
                case .nameAsc:
                    return a.title.localizedCompare(b.title) == .orderedAscending
                case .addedNewest:
                    return a.addedAt > b.addedAt
                case .addedOldest:
                    return a.addedAt < b.addedAt
                }
            }
    }

    var body: some View {
        LiveContent(isDead: !trip.isAlive) {
        Group {
            let _ = remoteChangeToken
            if sortedDocuments.isEmpty {
                ContentUnavailableView("No documents yet",
                                       systemImage: "doc.fill",
                                       description: Text("Add passports, visas, and boarding passes."))
            } else if viewMode == .grid {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(sortedDocuments) { doc in
                            documentTile(doc)
                        }
                    }
                    .padding()
                }
            } else {
                List {
                    ForEach(sortedDocuments) { doc in
                        documentRow(doc)
                            .listRowBackground(ThemeTokens.backgroundCard)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .refreshable { await PersistenceController.shared.manualRefresh() }
        .onReceive(NotificationCenter.default.publisher(for: .dayThreadRemoteChangeDidApply)) { _ in
            remoteChangeToken &+= 1
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Sort menu
                Menu {
                    ForEach(DocumentSortOrder.allCases, id: \.self) { order in
                        Button {
                            sortOrder = order
                        } label: {
                            Label(
                                order.rawValue,
                                systemImage: sortOrder == order ? "checkmark" : ""
                            )
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }

                // Grid / list toggle
                Button {
                    viewModeRaw = (viewMode == .grid) ? DocumentViewMode.list.rawValue
                                                      : DocumentViewMode.grid.rawValue
                } label: {
                    Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                }

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
    }

    // MARK: — Grid tile

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
        .contextMenu { contextMenuItems(doc) }
    }

    // MARK: — List row

    @ViewBuilder
    private func documentRow(_ doc: TripDocument) -> some View {
        Button {
            viewingDocument = doc
        } label: {
            HStack(spacing: 12) {
                // Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(ThemeTokens.backgroundPrimary)
                        .frame(width: 56, height: 56)

                    if doc.mimeType != "application/pdf",
                       let data = doc.documentData,
                       let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: doc.mimeType == "application/pdf" ? "doc.fill" : "photo.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(ThemeTokens.accent)
                    }
                }

                // Text info
                VStack(alignment: .leading, spacing: 3) {
                    Text(doc.title.isEmpty ? "Untitled" : doc.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(ThemeTokens.textPrimary)
                        .lineLimit(1)

                    if !doc.notes.isEmpty {
                        Text(doc.notes)
                            .font(.caption)
                            .foregroundStyle(ThemeTokens.textSecondary)
                            .lineLimit(2)
                    }

                    if let expiry = doc.expiryDate {
                        expiryLabel(expiry)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .contextMenu { contextMenuItems(doc) }
    }

    // MARK: — Shared context menu

    @ViewBuilder
    private func contextMenuItems(_ doc: TripDocument) -> some View {
        // Locked documents: only the originator can edit or delete.
        if !doc.isLocked || isOriginator(doc) {
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

    // MARK: — Expiry indicators

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

    @ViewBuilder
    private func expiryLabel(_ date: Date) -> some View {
        let daysUntil = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
        let color: Color = daysUntil < 0 ? .red
                         : daysUntil < 30 ? .red
                         : daysUntil < 90 ? ThemeTokens.warningAmber
                         : ThemeTokens.textMuted
        HStack(spacing: 3) {
            Image(systemName: "calendar")
                .font(.caption2)
            Text(daysUntil < 0 ? "Expired"
                 : daysUntil == 0 ? "Expires today"
                 : "Expires \(date.formatted(.dateTime.day().month(.abbreviated).year()))")
                .font(.caption2)
        }
        .foregroundStyle(color)
    }
}

// MARK: — Document viewer

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
            .safeAreaInset(edge: .bottom) {
                if !document.notes.isEmpty {
                    HStack {
                        Image(systemName: "note.text")
                            .foregroundStyle(ThemeTokens.textSecondary)
                        Text(document.notes)
                            .font(.subheadline)
                            .foregroundStyle(ThemeTokens.textSecondary)
                            .lineLimit(3)
                        Spacer()
                    }
                    .padding()
                    .background(.regularMaterial)
                }
            }
            .task {
                guard let data = document.documentData else { return }
                let ext = document.mimeType == "application/pdf" ? "pdf" : "jpg"
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(ext)
                try? data.write(to: url)
                tempURL = url
            }
            .onDisappear {
                if let url = tempURL {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }
}

// MARK: — QuickLook wrapper

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
