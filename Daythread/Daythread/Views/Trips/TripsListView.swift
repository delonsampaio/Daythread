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

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Trip.startDate, ascending: true)])
    private var allTrips: FetchedResults<Trip>
    @State private var vm = TripsViewModel()
    @State private var showCreate = false
    @State private var editingTrip: Trip?
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
            .onAppear { now = Date() }
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
                            vm.deleteTrip(trip, context: context)
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
