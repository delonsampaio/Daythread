//
//  DocumentGridView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import SwiftData
import QuickLook

struct DocumentGridView: View {
    let trip: Trip
    let vm: VaultViewModel

    @Environment(\.modelContext) private var context
    @Environment(TripStore.self) private var store
    @State private var showAdd = false
    @State private var viewingDocument: TripDocument?

    private let columns = [GridItem(.adaptive(minimum: 100))]

    var body: some View {
        Group {
            if (trip.documents ?? []).isEmpty {
                ContentUnavailableView("No documents yet",
                                       systemImage: "doc.fill",
                                       description: Text("Add passports, visas, and boarding passes."))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(trip.documents ?? []) { doc in
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
            Button("Delete", role: .destructive) {
                vm.deleteDocument(doc, context: context)
            }
        }
    }

    @ViewBuilder
    private func expiryBadge(_ date: Date) -> some View {
        let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        let color: Color = daysUntil < 0 ? .red : daysUntil < 30 ? ThemeTokens.warningAmber : .clear
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

private struct DocumentViewerSheet: View {
    let document: TripDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let data = document.documentData {
                    QuickLookPreviewView(data: data, title: document.title, mimeType: document.mimeType)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("No file data", systemImage: "doc.badge.exclamationmark")
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: — QuickLook wrapper

private struct QuickLookPreviewView: UIViewControllerRepresentable {
    let data: Data
    let title: String
    let mimeType: String

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(data: data, title: title, mimeType: mimeType) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        private let tempURL: URL

        init(data: Data, title: String, mimeType: String) {
            let ext = mimeType == "application/pdf" ? "pdf" : "jpg"
            let safeTitle = title.components(separatedBy: .init(charactersIn: "/\\:")).joined(separator: "-")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(safeTitle)
                .appendingPathExtension(ext)
            try? data.write(to: url)
            self.tempURL = url
            super.init()
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            tempURL as NSURL
        }
    }
}
