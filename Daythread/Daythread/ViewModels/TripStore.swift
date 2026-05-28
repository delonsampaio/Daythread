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
    var activeTrip: Trip?
    var syncStatus: CloudKitSyncStatus = .idle

    /// Persisted to UserDefaults so Pro status survives app restarts.
    /// The didSet syncs every write back to disk immediately.
    var isPro: Bool = UserDefaults.standard.bool(forKey: "daythread.isPro") {
        didSet { UserDefaults.standard.set(isPro, forKey: "daythread.isPro") }
    }
}
