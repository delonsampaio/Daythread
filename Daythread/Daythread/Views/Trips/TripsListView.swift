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

    private var currentTrips: [Trip]  { allTrips.filter { !$0.isArchived && $0.startDate <= now && $0.endDate >= now } }
    private var upcomingTrips: [Trip] { allTrips.filter { !$0.isArchived && $0.startDate > now } }
    private var pastTrips: [Trip]     { allTrips.filter { !$0.isArchived && $0.endDate < now } }
    private var archivedTrips: [Trip] { allTrips.filter(\.isArchived) }

    var body: some View {
        NavigationStack {
            Group {
                if allTrips.filter({ !$0.isArchived }).isEmpty {
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
                for trip in allTrips where trip.cloudKitShareID != nil {
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
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "suitcase.fill")
                .font(.system(size: 56))
                .foregroundStyle(ThemeTokens.textMuted)
            Text("No trips yet")
                .font(.title2.bold())
            Text("Tap + to plan your first adventure.")
                .font(.subheadline)
                .foregroundStyle(ThemeTokens.textSecondary)
            Button("Create a Trip") { showCreate = true }
                .buttonStyle(.borderedProminent)
                .tint(ThemeTokens.accent)
            Spacer()
        }
        .padding()
    }
}
