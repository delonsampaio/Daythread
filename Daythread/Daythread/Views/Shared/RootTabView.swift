//
//  RootTabView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData

enum DaythreadTab {
    case timeline, trips, vault, profile
}

struct RootTabView: View {
    @Environment(TripStore.self) private var store
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "isArchived == NO")) private var activeTrips: FetchedResults<Trip>

    @State private var selectedTab: DaythreadTab = .timeline

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Timeline", systemImage: ThemeTokens.tabTimeline, value: DaythreadTab.timeline) {
                TimelineView()
            }
            Tab("Trips", systemImage: ThemeTokens.tabTrips, value: DaythreadTab.trips) {
                TripsListView()
            }
            Tab("Vault", systemImage: ThemeTokens.tabVault, value: DaythreadTab.vault) {
                VaultView()
            }
            Tab("Profile", systemImage: ThemeTokens.tabProfile, value: DaythreadTab.profile) {
                ProfileView()
            }
        }
        .onAppear {
            selectedTab = .timeline
            // Set activeTrip to the first non-archived trip on launch
            if store.activeTrip == nil {
                store.activeTrip = activeTrips.first
            }
        }
        // FetchedResults<Trip> is not Equatable so we compare IDs to detect changes.
        .onChange(of: activeTrips.map(\.id)) { _, _ in
            let trips = Array(activeTrips)
            // A freshly accepted shared trip may have just synced in — switch to
            // it before the generic fallback logic picks an arbitrary first trip.
            store.resolvePendingJoin(in: trips)

            if store.activeTrip == nil {
                // Covers two cases:
                // 1. Reinstall — CloudKit syncs data after onAppear fired with empty results
                // 2. Race where @FetchRequest hasn't returned data yet when onAppear ran
                store.activeTrip = trips.first
            } else if let active = store.activeTrip,
                      // Guard first: accessing @NSManaged id on a deleted object whose
                      // context was set to nil causes NSObjectInaccessibleException.
                      // Swift || short-circuits, so id is only accessed when context is live.
                      active.managedObjectContext == nil ||
                      !trips.contains(where: { $0.id == active.id }) {
                // Active trip was deleted or archived — fall back to another trip
                store.activeTrip = trips.first
            }
        }
    }
}
