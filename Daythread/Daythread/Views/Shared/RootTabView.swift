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
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "isArchived == NO")) private var activeTrips: FetchedResults<Trip>
    @State private var cloudKit = CloudKitService()

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
            store.selectInitialTripIfNeeded(from: Array(activeTrips))
        }
        // Sync participants whenever the active shared trips change (e.g. a new
        // co-editor accepts) so avatar stacks update without opening GroupSync.
        .onChange(of: activeTrips.map(\.id)) { _, _ in
            for trip in activeTrips where trip.cloudKitShareID != nil {
                cloudKit.syncParticipants(for: trip, context: context)
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
                // Restore the last-used trip if it has now synced in.
                store.selectInitialTripIfNeeded(from: trips)
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
