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

    // MARK: — Current-user identity (for the named member roster)

    /// The current iCloud user's record name — a stable per-account identity used
    /// to register the user as a real trip member. Device-only; returns nil on
    /// the simulator or when iCloud is unavailable.
    func currentUserRecordName() async -> String? {
        do { return try await backend.container.userRecordID().recordName }
        catch {
            errorMessage = nil   // identity lookup is best-effort; don't alarm the user
            return nil
        }
    }

    /// True when the current user owns the trip's CKShare (vs. a participant).
    /// Used to register the owner as admin and joiners as editors.
    func currentUserIsOwner(of trip: Trip) -> Bool {
        guard let share = try? backend.existingShare(for: trip) else { return false }
        return share.currentUserParticipant?.role == .owner
    }

    /// Syncs all accepted CKShare participants into TripMember records so the
    /// owner sees co-editors immediately after they accept — without waiting for
    /// each person to open GroupSyncSheet themselves. Called when GroupSyncSheet
    /// appears; device-only and best-effort.
    func syncParticipants(for trip: Trip, context: NSManagedObjectContext) {
        guard let share = try? backend.existingShare(for: trip) else { return }
        let formatter = PersonNameComponentsFormatter()
        for participant in share.participants
        where participant.acceptanceStatus == .accepted {
            guard let uid = participant.userIdentity.userRecordID?.recordName else { continue }
            let role: MemberRole = participant.role == .owner ? .admin :
                (participant.permission == .readOnly ? .viewer : .editor)
            // Prefer the name the participant set themselves (stored in their
            // TripMember.displayName). Fall back to iCloud nameComponents, then
            // a placeholder so the slot is never blank.
            let existing = trip.membersArray.first {
                !$0.appleUserID.isEmpty && $0.appleUserID == uid
            }
            let name: String = {
                if let e = existing, !e.displayName.isEmpty { return e.displayName }
                if let nc = participant.userIdentity.nameComponents,
                   !formatter.string(from: nc).isEmpty {
                    return formatter.string(from: nc)
                }
                return "Traveler"
            }()
            TripMemberRegistry.upsertCurrentUser(
                in: trip, appleUserID: uid, displayName: name, role: role, context: context
            )
        }
        try? context.save()
    }

    /// Registers the current iCloud user as a real member of a shared trip
    /// (owner → admin, joiner → editor) so co-editors see real names + roles.
    /// Device-only and best-effort: no-op when the trip isn't shared or identity
    /// is unavailable. `displayName` falls back to "Me" when blank.
    func registerCurrentUserMembership(
        in trip: Trip,
        displayName: String,
        context: NSManagedObjectContext
    ) async {
        guard trip.cloudKitShareID != nil else { return }
        guard let uid = await currentUserRecordName() else { return }
        let role: MemberRole = currentUserIsOwner(of: trip) ? .admin : .editor
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        TripMemberRegistry.upsertCurrentUser(
            in: trip,
            appleUserID: uid,
            displayName: trimmed.isEmpty ? "Me" : trimmed,
            role: role,
            context: context
        )
        try? context.save()
    }
}
