//
//  TripStore.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import Foundation
import Observation

enum CloudKitSyncStatus: Equatable {
    case idle
    case syncing
    case error(String)
}

@Observable
final class TripStore {

    // MARK: — Active trip

    /// In-memory active trip. Setting it persists the ID to UserDefaults so
    /// the same trip can be restored on cold launch (see TimelineView.task).
    var activeTrip: Trip? {
        didSet {
            UserDefaults.standard.set(
                activeTrip?.id.uuidString,
                forKey: "daythread.activeTripID"
            )
        }
    }

    /// The UUID stored at last launch — used to restore context on cold launch.
    var storedActiveTripID: UUID? {
        UserDefaults.standard.string(forKey: "daythread.activeTripID")
            .flatMap { UUID(uuidString: $0) }
    }

    /// Picks the active trip on cold launch: the last-used trip (by persisted
    /// UUID) if it's still present, otherwise the first trip. No-op when a trip
    /// is already active, so it never clobbers an in-session selection.
    ///
    /// This must be the single entry point for launch selection. Setting
    /// `activeTrip = trips.first` directly would fire `didSet` and overwrite the
    /// persisted last-used ID before it could be read — destroying the user's
    /// remembered choice (the cause of the "wrong trip on launch" bug).
    func selectInitialTripIfNeeded(from trips: [Trip]) {
        guard activeTrip == nil else { return }
        if let id = storedActiveTripID,
           let match = trips.first(where: { $0.id == id }) {
            activeTrip = match
        } else {
            activeTrip = trips.first
        }
    }

    // MARK: — Pending share join

    /// Set when a CKShare is accepted (via a tapped invite link) but the joined
    /// Trip hasn't synced into the local store yet. A view with @Query trips
    /// resolves and clears this once the matching trip arrives — see
    /// ShareDeepLinkHandler and RootTabView's resolution onChange.
    var pendingJoinShareRecordName: String?

    /// If a pending share-join is waiting and a matching trip is now present in
    /// `trips`, make it active and clear the pending name. No-op when there is no
    /// pending join or the trip hasn't synced in yet (the name is retained).
    func resolvePendingJoin(in trips: [Trip]) {
        guard let recordName = pendingJoinShareRecordName else { return }
        guard let match = ShareDeepLinkHandler.trip(forShareRecordName: recordName, in: trips)
        else { return }
        activeTrip = match
        pendingJoinShareRecordName = nil
    }

    // MARK: — Other state

    var syncStatus: CloudKitSyncStatus = .idle

    /// Persisted to UserDefaults so Pro status survives app restarts.
    var isPro: Bool = UserDefaults.standard.bool(forKey: "daythread.isPro") {
        didSet { UserDefaults.standard.set(isPro, forKey: "daythread.isPro") }
    }
}
