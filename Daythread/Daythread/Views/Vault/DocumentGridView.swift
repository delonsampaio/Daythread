//
//  DocumentGridView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import SwiftData

struct DocumentGridView: View {
    let trip: Trip
    let vm: VaultViewModel

    @Environment(\.modelContext) private var context
    @Environment(TripStore.self) private var store
    @State private var showAdd = false

    private let columns = [GridItem(.adaptive(minimum: 100))]

    var body: some View {
        Group {
            if (trip.documents ?? []).isEmpty {
                ContentUnavailableView("No documents yet",
                                       systemImage: "doc.fill",
                                       description: Text("Add passports, visas, and boarding passes."))
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(trip.documents ?? []) { doc in
                        documentTile(doc)
                    }
                }
                .padding()
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
    }

    @ViewBuilder
    private func documentTile(_ doc: TripDocument) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(ThemeTokens.backgroundCard)
                    .frame(height: 90)
                Image(systemName: doc.mimeType == "application/pdf" ? "doc.fill" : "photo.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(ThemeTokens.accent)

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
