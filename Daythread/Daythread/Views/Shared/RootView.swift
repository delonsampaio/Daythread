//
//  RootView.swift
//  Daythread
//
//  Created by Delon Sampaio on 6/1/26.
//

import Combine
import CoreData
import SwiftUI

struct RootView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.managedObjectContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "isArchived == NO")) private var activeTrips: FetchedResults<Trip>
    @State private var cloudKit = CloudKitService()
    @State private var selectedTab: DaythreadTab = .timeline

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                RootTabView(selectedTab: $selectedTab)
            } else {
                RootSplitView(selectedTab: $selectedTab)
            }
        }
        .onAppear {
            selectedTab = .timeline
            store.selectInitialTripIfNeeded(from: Array(activeTrips))
        }
        // Sync participants whenever the active shared trips change (e.g. a new
        // co-editor accepts) so avatar stacks update without opening GroupSync.
        // Use objectID (always non-nil) not .id (UUID, can be nil on a partially-
        // synced CloudKit record) to avoid UUID bridging crashes during sync.
        .onChange(of: activeTrips.map(\.objectID)) { _, _ in
            for trip in activeTrips where trip.cloudKitShareID != nil {
                cloudKit.syncParticipants(for: trip, context: context)
            }
        }
        // Safety net for passive share revocation: when the share owner removes a
        // participant (or stops sharing) while that device is offline, there is no
        // UICloudSharingController callback — the shared zone is purged silently
        // during the next CloudKit import. Watching import events lets us redirect
        // before any view touches the now-invalid NSManagedObject and crashes with
        // NSObjectInaccessibleException. Read-only — no CoreData writes — so this
        // cannot cause the NSPersistentStoreRemoteChangeNotification write loop.
        .onReceive(
            NotificationCenter.default
                .publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.type == .import,
                  event.endDate != nil
            else { return }
            // Hop to MainActor explicitly — TripStore is @Observable (not @MainActor)
            // and DispatchQueue.main is a different isolation domain in Swift 6 strict
            // concurrency, so using receive(on: DispatchQueue.main) still triggers the
            // "Publishing changes from background threads" warning.
            Task { @MainActor in
                if let active = store.activeTrip, active.managedObjectContext == nil {
                    store.activeTrip = Array(activeTrips).first(where: { $0.managedObjectContext != nil })
                }
                // Resolve a pending share-join after every CloudKit import. This is
                // the most reliable trigger: the import-complete event fires after
                // NSPersistentCloudKitContainer has written the accepted shared trip
                // into the store, so activeTrips is guaranteed to include it.
                store.resolvePendingJoin(in: Array(activeTrips))
                // Sync participants after every CloudKit import. The
                // onChange(of: objectIDs) trigger misses participant-acceptance
                // events because accepting a CKShare invite doesn't change the
                // trip's objectID — only the CKShare's participant list in CloudKit.
                for trip in activeTrips where trip.cloudKitShareID != nil && trip.isAlive {
                    cloudKit.syncParticipants(for: trip, context: context)
                }
            }
        }
        // FetchedResults<Trip> is not Equatable so we compare IDs to detect changes.
        // compactMap with value(forKey:) so partially-synced CloudKit records
        // (whose @NSManaged id UUID may still be nil) don't crash the bridge.
        .onChange(of: activeTrips.compactMap { $0.value(forKey: "id") as? UUID }) { _, _ in
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
        // CloudKit syncs attributes piecemeal: a new shared trip's `id` may arrive
        // before its `cloudKitShareID`, causing the onChange(of: ids) above to fire
        // before resolvePendingJoin can find a match. Watch cloudKitShareID too so
        // we retry the moment the matching attribute arrives.
        .onChange(of: activeTrips.compactMap(\.cloudKitShareID)) { _, _ in
            store.resolvePendingJoin(in: Array(activeTrips))
        }
    }
}
