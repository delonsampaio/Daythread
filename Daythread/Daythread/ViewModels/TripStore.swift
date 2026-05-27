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
    var isPro: Bool = false
}
