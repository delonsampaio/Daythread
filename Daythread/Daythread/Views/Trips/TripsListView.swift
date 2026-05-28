//
//  TripsListView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import SwiftData

struct TripsListView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.modelContext) private var context

    @Query(sort: \Trip.startDate) private var allTrips: [Trip]
    @State private var vm = TripsViewModel()
    @State private var showCreate = false

    private var currentTrips: [Trip]  { allTrips.filter { !$0.isArchived && $0.startDate <= Date() && $0.endDate >= Date() } }
    private var upcomingTrips: [Trip] { allTrips.filter { !$0.isArchived && $0.startDate > Date() } }
    private var pastTrips: [Trip]     { allTrips.filter { !$0.isArchived && $0.endDate < Date() } }
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
                        Button("Set as Active") { store.activeTrip = trip }
                        if trip.isArchived {
                            Button("Unarchive") { vm.unarchiveTrip(trip, context: context) }
                        } else {
                            Button("Archive") { vm.archiveTrip(trip, context: context) }
                        }
                        Button("Delete", role: .destructive) { vm.deleteTrip(trip, context: context) }
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
