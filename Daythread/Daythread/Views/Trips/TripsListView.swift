//
//  TripsListView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData

struct TripsListView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(TripStore.self) private var store

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Trip.startDate, ascending: true)])
    private var allTrips: FetchedResults<Trip>
    @State private var vm = TripsViewModel()
    @State private var cloudKit = CloudKitService()
    @State private var showCreate = false
    @State private var editingTrip: Trip?
    @State private var tripPendingDelete: Trip?
    // Single snapshot per render — prevents repeated Date() calls from causing
    // trips to flip between sections mid-scroll if the clock ticks.
    @State private var now = Date()

    /// Deduplicated trip list. During the migration window NSPCKC can re-import
    /// the original into the private store before its CloudKit deletion propagates,
    /// producing two Trip objects with the same id (original + clone). Keep the
    /// shared-store clone (.migration == .done) when both exist.
    private var deduplicatedTrips: [Trip] {
        var seen: [UUID: Trip] = [:]
        for trip in allTrips {
            guard let id = trip.id else { continue }
            if let existing = seen[id] {
                // Prefer the shared-store clone over any private-store duplicate.
                let tripIsClone = trip.objectID.persistentStore?.url?.lastPathComponent == "shared.sqlite"
                if tripIsClone { seen[id] = trip } else { _ = existing }
            } else {
                seen[id] = trip
            }
        }
        return allTrips.filter { trip in trip.id.map { seen[$0]?.objectID == trip.objectID } ?? false }
    }

    private var currentTrips: [Trip]  { deduplicatedTrips.filter { !$0.isArchived && $0.startDate <= now && $0.endDate >= now } }
    private var upcomingTrips: [Trip] { deduplicatedTrips.filter { !$0.isArchived && $0.startDate > now } }
    private var pastTrips: [Trip]     { deduplicatedTrips.filter { !$0.isArchived && $0.endDate < now } }
    private var archivedTrips: [Trip] { deduplicatedTrips.filter(\.isArchived) }

    var body: some View {
        NavigationStack {
            Group {
                if deduplicatedTrips.filter({ !$0.isArchived }).isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            tripSection("Current", trips: currentTrips)
                            tripSection("Upcoming", trips: upcomingTrips)
                            tripSection("Past", trips: pastTrips)
                            if !archivedTrips.isEmpty {
                                tripSection("Archived", trips: archivedTrips)
                            }
                        }
                        .padding()
                    }
                    .refreshable { await PersistenceController.shared.manualRefresh() }
                }
            }
            .navigationTitle("Trips")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateTripSheet()
            }
            .sheet(item: $editingTrip) { trip in
                EditTripSheet(trip: trip, vm: vm)
            }
            .alert("Delete Trip?", isPresented: Binding(
                get: { tripPendingDelete != nil },
                set: { if !$0 { tripPendingDelete = nil } }
            ), presenting: tripPendingDelete) { trip in
                Button("Delete", role: .destructive) {
                    // Clear the active trip first so the Timeline tab stops
                    // observing the about-to-be-deleted graph (see use-after-delete fix).
                    if store.activeTrip?.objectID == trip.objectID {
                        store.activeTrip = nil
                    }
                    vm.deleteTrip(trip, context: context)
                    tripPendingDelete = nil
                }
                Button("Cancel", role: .cancel) { tripPendingDelete = nil }
            } message: { trip in
                Text("This permanently deletes \u{201C}\(trip.name)\u{201D} and all its days, events, documents, and expenses. This can't be undone.")
            }
            .onAppear {
                now = Date()
                // Sync participants for every shared trip so avatar stacks on
                // trip cards populate without the user having to open GroupSync.
                for trip in deduplicatedTrips where trip.cloudKitShareID != nil {
                    cloudKit.syncParticipants(for: trip, context: context)
                }
            }
        }
    }

    @ViewBuilder
    private func tripSection(_ title: String, trips: [Trip]) -> some View {
        if !trips.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)

                ForEach(trips) { trip in
                    NavigationLink {
                        PreTripTasksView(trip: trip, vm: vm)
                    } label: {
                        TripCardView(trip: trip)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") {
                            editingTrip = trip
                        }
                        Divider()
                        if trip.isArchived {
                            Button("Unarchive", systemImage: "archivebox") {
                                vm.unarchiveTrip(trip, context: context)
                            }
                        } else {
                            Button("Archive", systemImage: "archivebox") {
                                vm.archiveTrip(trip, context: context)
                            }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            tripPendingDelete = trip
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "airplane.departure")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(ThemeTokens.accent.opacity(0.7))
                .padding(.bottom, 28)
            Text("No trips yet")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(ThemeTokens.textPrimary)
                .padding(.bottom, 10)
            Text("Plan your first adventure and invite\nyour travel crew to join.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(ThemeTokens.textSecondary)
                .padding(.horizontal, 48)
                .padding(.bottom, 32)
            Button {
                showCreate = true
            } label: {
                Label("Create Your First Trip", systemImage: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(ThemeTokens.accent))
            }
            Spacer()
            Spacer()
        }
        .padding()
    }
}
