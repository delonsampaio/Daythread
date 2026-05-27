//
//  RootTabView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import SwiftData

enum DaythreadTab {
    case timeline, trips, vault, profile
}

struct RootTabView: View {
    @Environment(TripStore.self) private var store
    @Query(filter: #Predicate<Trip> { !$0.isArchived }) private var activeTrips: [Trip]

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
        .onChange(of: activeTrips) { _, trips in
            // If active trip was deleted or archived, reset
            if let active = store.activeTrip, !trips.contains(where: { $0.id == active.id }) {
                store.activeTrip = trips.first
            }
        }
    }
}
