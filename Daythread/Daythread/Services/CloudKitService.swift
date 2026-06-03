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
import UIKit
import os

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
            let share = try await makeShareResilient(for: trip)
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

    /// Works around an NSPersistentCloudKitContainer bug: `share([trip], to:)`
    /// frequently CREATES the CKShare but never returns while the container is busy
    /// mirroring (constant export cycles), which froze the "Invite People" spinner
    /// indefinitely. The share metadata does land in Core Data during the hang, so
    /// we kick `share()` off in the background and poll `fetchShares` for the share
    /// it creates — returning the moment it appears instead of waiting on `share()`.
    /// The unawaited `share()` task is left to finish on its own (NSPCKC ignores
    /// cancellation); recovering via fetchShares is what unblocks the UI.
    private func makeShareResilient(for trip: Trip) async throws -> CKShare {
        // Fast path: already shared (e.g. created on a previous, hung attempt).
        if let existing = try backend.existingShare(for: trip) {
            return existing
        }
        // Inherits @MainActor isolation (CloudKitService is @MainActor), so passing
        // the non-Sendable `trip` into the task is safe — it never leaves the actor.
        let shareTask = Task { try await backend.makeShare(for: trip) }
        // Poll ~10s for the share share() persists mid-hang.
        for _ in 0..<20 {
            do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
            if let created = try? backend.existingShare(for: trip) {
                daythreadLog.log("makeShareResilient: recovered share via fetchShares")
                shareTask.cancel()   // best-effort; NSPCKC may ignore it
                created[CKShare.SystemFieldKey.title] = trip.name as CKRecordValue
                return created
            }
        }
        // share() never persisted a share in time — fall back to its return value,
        // which surfaces the real result (or error) instead of spinning forever.
        daythreadLog.log("makeShareResilient: poll exhausted — awaiting share() directly")
        return try await shareTask.value
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
        // Remove all real co-editor members — virtual (expense-only) members
        // are unrelated to CloudKit sharing and must be preserved.
        for member in trip.membersArray where !member.appleUserID.isEmpty {
            modelContext.delete(member)
        }
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
            guard let uid = participant.userIdentity.userRecordID?.recordName,
                  uid != "__defaultOwner__" else {
                // "__defaultOwner__" is a CloudKit placeholder — not a stable real
                // user ID. Skip it here; registerMyMembership uses
                // container.userRecordID() which returns the true record name.
                continue
            }
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
        deduplicateMembers(for: trip, context: context)
        try? context.save()
    }

    /// Removes duplicate TripMember records that arise when two devices
    /// independently register the same person before each other's record syncs.
    /// Matches first by appleUserID, then falls back to displayName for the case
    /// where syncParticipants and registerMyMembership produce different ID
    /// formats for the same real person. Keeps the highest-role record.
    func deduplicateMembers(for trip: Trip, context: NSManagedObjectContext) {
        // Use a fresh fetch so we see ALL members in the store, not just those
        // already loaded into the relationship cache.
        let request = TripMember.fetchRequest()
        request.predicate = NSPredicate(format: "trip == %@", trip)
        guard let allMembers = try? context.fetch(request) else { return }

        // Remove stale "__defaultOwner__" placeholder records — CloudKit uses this
        // as a sentinel for the share owner but it is not a real user identity.
        // registerMyMembership writes the true record name via container.userRecordID().
        for m in allMembers where m.appleUserID == "__defaultOwner__" {
            context.delete(m)
        }
        let live = allMembers.filter { !$0.isDeleted }

        let real = live.filter { !$0.appleUserID.isEmpty }
        var byUID: [String: TripMember] = [:]
        for m in real {
            let uid = m.appleUserID
            if let existing = byUID[uid] {
                let keepNew = rolePriority(m.role) > rolePriority(existing.role)
                    || (m.role == existing.role && m.joinedAt < existing.joinedAt)
                context.delete(keepNew ? existing : m)
                if keepNew { byUID[uid] = m }
            } else {
                byUID[uid] = m
            }
        }

        // Secondary pass: dedup by name for cases where two code paths produced
        // different appleUserID formats for the same real person.
        let remaining = live.filter { !$0.isDeleted && !$0.appleUserID.isEmpty }
        var byName: [String: TripMember] = [:]
        for m in remaining {
            let name = m.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !name.isEmpty else { continue }
            if let existing = byName[name] {
                let keepNew = rolePriority(m.role) > rolePriority(existing.role)
                    || (m.role == existing.role && m.joinedAt < existing.joinedAt)
                context.delete(keepNew ? existing : m)
                if keepNew { byName[name] = m }
            } else {
                byName[name] = m
            }
        }
    }

    /// Removes any real (non-virtual) TripMembers from a trip that is no longer
    /// shared. Called reactively when a NSPersistentStoreRemoteChangeNotification
    /// arrives for a trip whose cloudKitShareID is nil — handles the race where
    /// a co-editor's self-registered record syncs in AFTER stop-sharing propagates.
    func clearStaleRealMembers(for trip: Trip, context: NSManagedObjectContext) {
        guard trip.cloudKitShareID == nil else { return }
        let request = TripMember.fetchRequest()
        request.predicate = NSPredicate(format: "trip == %@ AND appleUserID != ''", trip)
        guard let stale = try? context.fetch(request), !stale.isEmpty else { return }
        stale.forEach { context.delete($0) }
        try? context.save()
    }

    private func rolePriority(_ role: MemberRole) -> Int {
        switch role { case .admin: return 2; case .editor: return 1; case .viewer: return 0 }
    }

    /// Registers the current iCloud user as a real member of a shared trip
    /// (owner → admin, joiner → editor) so co-editors see real names + roles.
    /// Device-only and best-effort: no-op when the trip isn't shared or identity
    /// is unavailable. Name resolution priority:
    /// 1. Custom name set in Profile → Settings (non-empty)
    /// 2. Name from CKShare currentUserParticipant.userIdentity.nameComponents
    ///    (same name the system sharing sheet shows)
    /// 3. "Traveler" placeholder — NOT the device name. UIDevice.current.name is
    ///    privacy-redacted to "iPhone"/"iPad" on iOS 16+, which is worse than a
    ///    neutral placeholder. The UI prompts the user to set a real name when sharing.
    func registerCurrentUserMembership(
        in trip: Trip,
        displayName: String,
        context: NSManagedObjectContext,
        store: TripStore? = nil
    ) async {
        guard trip.cloudKitShareID != nil else { return }
        guard let uid = await currentUserRecordName() else { return }
        store?.currentUserCloudKitID = uid
        let role: MemberRole = currentUserIsOwner(of: trip) ? .admin : .editor
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveName: String
        if !trimmed.isEmpty {
            effectiveName = trimmed
        } else if let share = existingShare(for: trip),
                  let nc = share.currentUserParticipant?.userIdentity.nameComponents,
                  !PersonNameComponentsFormatter().string(from: nc).isEmpty {
            effectiveName = PersonNameComponentsFormatter().string(from: nc)
        } else {
            effectiveName = "Traveler"
        }
        TripMemberRegistry.upsertCurrentUser(
            in: trip,
            appleUserID: uid,
            displayName: effectiveName,
            role: role,
            context: context
        )
        try? context.save()
    }

    // MARK: — Shared-database push subscription

    /// NSPersistentCloudKitContainer reliably creates the silent-push subscription
    /// for the PRIVATE database but is notorious for failing to create one for the
    /// SHARED database — so participants never get pushed when a co-editor changes
    /// something, and only sync at launch.
    ///
    /// CRITICAL: the subscription ID MUST be Core Data's own internal shared-DB
    /// subscription ID. The container's swizzled push handler inspects the incoming
    /// push for that exact subscriptionID and DROPS any push whose ID doesn't match —
    /// so a custom-ID subscription wakes the device but never triggers an import.
    /// Using the internal ID makes the container treat our push as its own and run
    /// the shared-DB import. CKModifySubscriptionsOperation is idempotent, so saving
    /// over the container's (possibly missing) subscription is safe.
    nonisolated func ensureSharedDatabaseSubscription() {
        let container = CKContainer(identifier: "iCloud.com.delonsampaio.daythread")
        let sharedDB = container.sharedCloudDatabase

        let subscription = CKDatabaseSubscription(subscriptionID: "com.apple.coredata.cloudkit.shared.subscription")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true   // silent push that wakes the app
        subscription.notificationInfo = info

        let op = CKModifySubscriptionsOperation(
            subscriptionsToSave: [subscription],
            subscriptionIDsToDelete: nil
        )
        op.qualityOfService = .utility
        op.modifySubscriptionsResultBlock = { result in
            switch result {
            case .success:
                daythreadLog.log("shared-DB silent-push subscription registered (internal ID)")
            case .failure(let error):
                daythreadLog.error("shared-DB subscription FAILED: \(error.localizedDescription, privacy: .public)")
            }
        }
        sharedDB.add(op)
    }

    /// DIAGNOSTIC: logs whether the shared database has any push subscriptions.
    nonisolated func verifySharedDatabaseSubscription() {
        let container = CKContainer(identifier: "iCloud.com.delonsampaio.daythread")
        container.sharedCloudDatabase.fetchAllSubscriptions { subs, error in
            if let error {
                daythreadLog.error("error fetching shared subscriptions: \(error.localizedDescription, privacy: .public)")
            } else if let subs, !subs.isEmpty {
                let ids = subs.map(\.subscriptionID).joined(separator: ", ")
                daythreadLog.log("shared-DB subscriptions: \(ids, privacy: .public)")
            } else {
                daythreadLog.error("NO shared-DB subscriptions — live push cannot arrive")
            }
        }
    }
}
