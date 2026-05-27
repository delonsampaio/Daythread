//
//  CloudKitService.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/27/26.
//
//  Placeholder implementation of CloudKit trip-sharing.
//  The real production implementation will use NSPersistentCloudKitContainer.share(_:to:)
//  in v1.0 Pro. This scaffold wires the UI without requiring an active iCloud account.

import CloudKit
import SwiftData
import Observation

@Observable
@MainActor
final class CloudKitService {
    var isSharing: Bool = false
    var errorMessage: String?

    /// Marks `trip` as shared by recording a placeholder share ID.
    /// Returns a `CKShare?` — nil in this scaffold; replace with a real share in production.
    func shareTrip(_ trip: Trip, modelContext: ModelContext) async -> CKShare? {
        guard trip.cloudKitShareID == nil else { return nil }
        do {
            let shareID = UUID().uuidString
            trip.cloudKitShareID = shareID
            try modelContext.save()
            isSharing = true
            return nil  // Replace with real CKShare from NSPersistentCloudKitContainer in v1.0
        } catch {
            errorMessage = "Could not create share: \(error.localizedDescription)"
            return nil
        }
    }

    func stopSharing(_ trip: Trip, modelContext: ModelContext) {
        trip.cloudKitShareID = nil
        try? modelContext.save()
        isSharing = false
    }

    var isAvailable: Bool {
        // Replace with async CKContainer.default().accountStatus check in production
        true
    }
}
