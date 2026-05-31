//
//  CloudKitService.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/27/26.
//
//  Trip co-editing via CloudKit sharing.
//
//  Architecture:
//  • CloudKitService — testable orchestration (reuse-vs-create, model mutation,
//    error handling). Depends only on the TripSharingBackend protocol.
//  • TripSharingBackend — the seam between orchestration and CloudKit network.
//  • CloudKitTripSharingBackend — the real, device-only implementation that
//    creates a CKShare. Cannot run on the simulator (no iCloud account; the
//    ModelContainer disables CloudKit there), so it is verified on-device only.
//

import CloudKit
import CoreData
import Observation

// MARK: — Backend seam

/// Abstracts the CloudKit network work of producing a CKShare for a trip,
/// so CloudKitService's orchestration can be unit-tested with a stub.
protocol TripSharingBackend {
    /// The container the resulting share belongs to — needed by
    /// UICloudSharingController when presenting the system invite sheet.
    var container: CKContainer { get }

    /// Creates (or returns) a CKShare for `trip`. Throws on any CloudKit failure.
    func makeShare(for trip: Trip) async throws -> CKShare

    /// Returns the existing CKShare for an already-shared trip (for participant
    /// management), or nil if the trip has no share. Throws on lookup failure.
    func existingShare(for trip: Trip) throws -> CKShare?
}

// MARK: — Orchestration (testable)

@Observable
@MainActor
final class CloudKitService {
    var isSharing: Bool = false
    var errorMessage: String?

    private let backend: TripSharingBackend

    init(backend: TripSharingBackend = CloudKitTripSharingBackend()) {
        self.backend = backend
    }

    /// The container backing the active share — exposed so the UI can hand it
    /// to UICloudSharingController alongside the CKShare.
    var container: CKContainer { backend.container }

    /// Creates a real CKShare for `trip` (or returns nil and reuses the existing
    /// share if the trip is already shared). On success, stamps the share's
    /// record name onto `trip.cloudKitShareID` and persists it. On failure,
    /// sets `errorMessage` and leaves the trip unshared.
    @discardableResult
    func shareTrip(_ trip: Trip, modelContext: NSManagedObjectContext) async -> CKShare? {
        // Already shared — caller should fetch the existing share to present.
        guard trip.cloudKitShareID == nil else {
            isSharing = true
            return nil
        }
        do {
            let share = try await backend.makeShare(for: trip)
            trip.cloudKitShareID = share.recordID.recordName
            try modelContext.save()
            isSharing = true
            errorMessage = nil
            return share
        } catch {
            errorMessage = "Could not create share: \(error.localizedDescription)"
            return nil
        }
    }

    /// Fetches the existing CKShare for an already-shared trip so the UI can
    /// present UICloudSharingController for participant management (add people,
    /// change permissions, stop sharing). Returns nil when the trip isn't shared
    /// or the lookup fails (setting `errorMessage` in the failure case).
    func existingShare(for trip: Trip) -> CKShare? {
        guard trip.cloudKitShareID != nil else { return nil }
        do {
            return try backend.existingShare(for: trip)
        } catch {
            errorMessage = "Could not load sharing details: \(error.localizedDescription)"
            return nil
        }
    }

    func stopSharing(_ trip: Trip, modelContext: NSManagedObjectContext) {
        trip.cloudKitShareID = nil
        try? modelContext.save()
        isSharing = false
    }
}
