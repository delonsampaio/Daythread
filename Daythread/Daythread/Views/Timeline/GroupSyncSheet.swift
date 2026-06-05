//
//  GroupSyncSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/27/26.
//

import SwiftUI
import CoreData
import CloudKit

// MARK: — Identifiable CKShare wrapper (needed for .sheet(item:))
// CKShare inherits Identifiable from NSObject (id: ObjectIdentifier), which
// cannot be overridden with a @retroactive extension. Wrapping gives us a
// stable String-based identity keyed on the record name.

private struct IdentifiableShare: Identifiable {
    let share: CKShare
    var id: String { share.recordID.recordName }
}

struct GroupSyncSheet: View {
    @ObservedObject var trip: Trip

    @Environment(TripStore.self) private var store
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage("daythread.userDisplayName") private var myName = ""

    /// Live fetch of this trip's real members so the list updates immediately
    /// when registerMyMembership saves a new record — without waiting for the
    /// @ObservedObject trip relationship cache to be invalidated.
    @FetchRequest private var members: FetchedResults<TripMember>

    init(trip: Trip) {
        self.trip = trip
        _members = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \TripMember.joinedAt, ascending: true)],
            predicate: NSPredicate(format: "trip == %@ AND appleUserID != ''", trip)
        )
    }

    @State private var cloudKit = CloudKitService()
    /// Non-nil while the UICloudSharingController sheet is presented.
    @State private var sharingSheet: IdentifiableShare? = nil
    /// True while the trip share is being prepared (migration in progress).
    @State private var isPreparing = false
    @State private var showNamePrompt = false
    @State private var nameInput = ""
    /// Captured before the system sheet opens while the CKShare still exists.
    /// UICloudSharingController deletes the share BEFORE cloudSharingControllerDidStopSharing
    /// fires, so checking isOwner inside that callback always returns false.
    @State private var isOwnerBeforeSheetOpen = false

    var body: some View {
        LiveContent(isDead: !trip.isAlive) {
        NavigationStack {
            List {
                // Migration-in-progress banner — blocks interaction while the
                // trip is being cloned / uploaded to the shared custom zone.
                if trip.migration == .cloned || trip.migration == .uploaded {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Setting up sharing…")
                                .font(.subheadline)
                                .foregroundStyle(ThemeTokens.textSecondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Share status
                Section("Co-editing") {
                    if trip.cloudKitShareID != nil {
                        // Tapping opens the system sharing sheet for the EXISTING
                        // share — add/remove people, change permissions, or stop
                        // sharing — without having to stop sharing first.
                        Button {
                            manageSharing()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.2.fill")
                                    .foregroundStyle(ThemeTokens.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Trip is shared")
                                        .foregroundStyle(ThemeTokens.textPrimary)
                                    Text("Manage people & permissions")
                                        .font(.caption)
                                        .foregroundStyle(ThemeTokens.textSecondary)
                                }
                                Spacer()
                                if isPreparing {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(ThemeTokens.textMuted)
                                }
                            }
                        }
                        .disabled(isPreparing)
                    } else {
                        if isPreparing {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Setting up sharing…")
                                    .foregroundStyle(ThemeTokens.textSecondary)
                            }
                            .padding(.vertical, 4)
                        } else {
                            Button {
                                inviteePeople()
                            } label: {
                                Label("Invite People to This Trip", systemImage: "person.badge.plus")
                                    .foregroundStyle(ThemeTokens.accent)
                            }
                            .disabled(trip.migration != .none && trip.migration != .done)
                        }
                    }
                }

                // Live-fetched real co-editors (FetchRequest updates immediately
                // when registerMyMembership saves, without waiting for the trip
                // relationship cache to be invalidated).
                if !members.isEmpty {
                    Section("Members (\(members.count))") {
                        ForEach(members) { member in
                            HStack(spacing: 12) {
                                memberAvatar(member)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.displayName)
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(member.role.displayName)
                                        .font(.caption)
                                        .foregroundStyle(ThemeTokens.textSecondary)
                                }
                            }
                        }
                    }
                }

                // Error banner
                if let error = cloudKit.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(trip.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $sharingSheet) { identifiable in
                CloudSharingControllerView(
                    share: identifiable.share,
                    container: cloudKit.container,
                    title: trip.name,
                    onStopSharing: {
                        sharingSheet = nil
                        cloudKit.stopSharing(trip, modelContext: context)
                        // Participants: navigate away before NSPersistentCloudKitContainer
                        // purges the shared zone. Owners: trip stays in the private
                        // store so keep it selected.
                        if !isOwnerBeforeSheetOpen, store.activeTrip?.objectID == trip.objectID {
                            store.activeTrip = nil
                        }
                    }
                )
                .ignoresSafeArea()
            }
            .task {
                // Sync all accepted share participants first so the owner
                // sees co-editors immediately (not just after they open the
                // app themselves). Then register the current user's own entry.
                cloudKit.syncParticipants(for: trip, context: context, fetchLive: true)
                // Resolve the live clone in case `trip` is the zombie NSPCKC original
                // (managedObjectContext == nil after Phase 3 purge). The zombie's
                // cloudKitShareID returns nil, causing the guard below to exit early
                // and skip the name prompt — the owner sees "Traveler" forever.
                let liveTrip = resolvedLiveTrip() ?? trip
                // Only register once the trip is actually shared.
                guard liveTrip.cloudKitShareID != nil else { return }
                // Always register immediately using the live trip object so the
                // owner's membership is written to the shared store, not a zombie.
                await cloudKit.registerCurrentUserMembership(in: liveTrip, displayName: myName, context: context, store: store)
                // After registering, offer a prompt to personalise the name only when
                // the profile name is still empty — the user may want a different name
                // than their iCloud account name, but it's non-blocking now.
                if myName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    nameInput = ""
                    showNamePrompt = true
                }
            }
            .alert("Your name", isPresented: $showNamePrompt) {
                TextField("Name", text: $nameInput)
                Button("Save") {
                    let trimmed = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    myName = trimmed
                    Task { await registerMyMembership() }
                }
                Button("Not now", role: .cancel) { }
            } message: {
                Text("Enter a name so co-travelers know who's who on this trip. You can change it later in Settings.")
            }
        }
        }
        .presentationSizing(.page)
    }

    // MARK: — Member avatar

    @ViewBuilder
    private func memberAvatar(_ member: TripMember) -> some View {
        ZStack {
            if let data = member.avatarData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(avatarColor(for: member))
                    .overlay(
                        Text(initials(for: member))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: 36, height: 36)
    }

    private func initials(for member: TripMember) -> String {
        let parts = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        switch parts.count {
        case 0:  return "?"
        case 1:  return String(parts[0].prefix(2)).uppercased()
        default: return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
    }

    private func avatarColor(for member: TripMember) -> Color {
        let colors: [Color] = [.blue, .purple, .teal, .orange, .pink, .indigo, .green]
        return colors[abs(member.displayName.hashValue) % colors.count]
    }

    /// Creates the CKShare (device-only) and presents the system invite sheet.
    /// On the simulator this surfaces an error via cloudKit.errorMessage rather
    /// than presenting, since CloudKit is unavailable there.
    private func inviteePeople() {
        isPreparing = true
        isOwnerBeforeSheetOpen = true
        // Capture the trip ID now — before the Task runs — so we can recover
        // the live clone even if `trip` becomes a zombie during migration.
        let capturedTripID = trip.id
        Task {
            // Resolve the live trip. During migration the NSPCKC original is purged;
            // trip.id returns nil on the zombie so we use the captured ID to find
            // the clone in shared.sqlite before calling shareTrip.
            let liveTrip: Trip
            if let id = capturedTripID {
                let request = Trip.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                request.fetchLimit = 1
                liveTrip = (try? context.fetch(request))?.first ?? trip
            } else {
                liveTrip = trip
            }
            let share = await cloudKit.shareTrip(liveTrip, modelContext: context)
            isPreparing = false
            if let share {
                sharingSheet = IdentifiableShare(share: share)
                cloudKit.seedNameFromShare(share, store: store)
                await registerMyMembership()
            }
        }
    }

    /// Registers the current iCloud user as a real member of this shared trip so
    /// co-editors see real names + roles instead of Apple's Contacts-dependent
    /// "Owner" label. Resolves the live clone when `trip` is a zombie (purged original).
    private func registerMyMembership() async {
        let liveTrip = resolvedLiveTrip() ?? trip
        await cloudKit.registerCurrentUserMembership(in: liveTrip, displayName: myName, context: context, store: store)
    }

    /// Returns the live Core Data object for this trip, resolving the shared-store
    /// clone when the original has been purged (managedObjectContext == nil).
    private func resolvedLiveTrip() -> Trip? {
        guard trip.managedObjectContext == nil, let tripID = trip.id else { return nil }
        let request = Trip.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", tripID as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Opens the system sharing sheet for the trip's EXISTING share so the user
    /// can manage participants and permissions without stopping sharing first.
    private func manageSharing() {
        guard let liveTrip = resolvedLiveTrip() ?? (trip.managedObjectContext != nil ? trip : nil) else {
            cloudKit.errorMessage = "Still setting up your share link. Please try again in a moment."
            return
        }

        isPreparing = true
        let share = cloudKit.existingShare(for: liveTrip)
        // Capture owner status BEFORE showing the sheet — UICloudSharingController
        // deletes the CKShare before cloudSharingControllerDidStopSharing fires,
        // so checking inside the callback always returns false.
        isOwnerBeforeSheetOpen = share?.currentUserParticipant?.role == .owner
        isPreparing = false
        if let share {
            sharingSheet = IdentifiableShare(share: share)
        } else {
            // Cache miss — the SyncState row may not have been written yet.
            // Fetch the share asynchronously and open the sheet when it arrives.
            isPreparing = true
            Task {
                if let share = try? await CloudKitTripSharingBackend().makeShare(for: liveTrip) {
                    isOwnerBeforeSheetOpen = share.currentUserParticipant?.role == .owner
                    sharingSheet = IdentifiableShare(share: share)
                } else {
                    cloudKit.errorMessage = "Could not load sharing details."
                }
                isPreparing = false
            }
        }
    }
}
