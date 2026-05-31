//
//  GroupSyncSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/27/26.
//

import SwiftUI
import CoreData
import CloudKit

struct GroupSyncSheet: View {
    @ObservedObject var trip: Trip

    @Environment(TripStore.self) private var store
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage("daythread.userDisplayName") private var myName = ""

    @State private var cloudKit = CloudKitService()
    @State private var pendingShare: CKShare?
    @State private var showShareSheet = false
    @State private var isPreparingShare = false

    var body: some View {
        NavigationStack {
            List {
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
                                if isPreparingShare {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(ThemeTokens.textMuted)
                                }
                            }
                        }
                        .disabled(isPreparingShare)
                    } else {
                        Button {
                            inviteePeople()
                        } label: {
                            HStack {
                                Label("Invite People to This Trip", systemImage: "person.badge.plus")
                                    .foregroundStyle(ThemeTokens.accent)
                                if isPreparingShare {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isPreparingShare)
                    }
                }

                // Only show real co-editors — virtual (expense-only) members
                // are managed in the Vault split-expenses sheet, not here.
                let members = trip.membersArray.filter { !$0.isVirtual }
                if !members.isEmpty {
                    Section("Members (\(members.count))") {
                        ForEach(members) { member in
                            HStack(spacing: 12) {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(ThemeTokens.textMuted)
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
            .sheet(isPresented: $showShareSheet) {
                if let share = pendingShare {
                    CloudSharingControllerView(
                        share: share,
                        container: cloudKit.container,
                        title: trip.name,
                        onStopSharing: { cloudKit.stopSharing(trip, modelContext: context) }
                    )
                    .ignoresSafeArea()
                }
            }
            .task {
                // Sync all accepted share participants first so the owner
                // sees co-editors immediately (not just after they open the
                // app themselves). Then register the current user's own entry.
                cloudKit.syncParticipants(for: trip, context: context)
                await registerMyMembership()
            }
        }
    }

    /// Creates the CKShare (device-only) and presents the system invite sheet.
    /// On the simulator this surfaces an error via cloudKit.errorMessage rather
    /// than presenting, since CloudKit is unavailable there.
    private func inviteePeople() {
        isPreparingShare = true
        Task {
            let share = await cloudKit.shareTrip(trip, modelContext: context)
            isPreparingShare = false
            if let share {
                pendingShare = share
                showShareSheet = true
                // Register the owner immediately so they appear in the roster.
                await registerMyMembership()
            }
        }
    }

    /// Registers the current iCloud user as a real member of this shared trip so
    /// co-editors see real names + roles instead of Apple's Contacts-dependent
    /// "Owner" label.
    private func registerMyMembership() async {
        await cloudKit.registerCurrentUserMembership(in: trip, displayName: myName, context: context, store: store)
    }

    /// Opens the system sharing sheet for the trip's EXISTING share so the user
    /// can manage participants and permissions without stopping sharing first.
    private func manageSharing() {
        isPreparingShare = true
        let share = cloudKit.existingShare(for: trip)
        isPreparingShare = false
        if let share {
            pendingShare = share
            showShareSheet = true
        }
    }
}
