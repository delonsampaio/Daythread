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

    /// The UUID stored at last launch — used by TimelineView to restore context on cold launch.
    var storedActiveTripID: UUID? {
        UserDefaults.standard.string(forKey: "daythread.activeTripID")
            .flatMap { UUID(uuidString: $0) }
    }

    // MARK: — Other state

    var syncStatus: CloudKitSyncStatus = .idle

    /// Persisted to UserDefaults so Pro status survives app restarts.
    var isPro: Bool = UserDefaults.standard.bool(forKey: "daythread.isPro") {
        didSet { UserDefaults.standard.set(isPro, forKey: "daythread.isPro") }
    }
}
