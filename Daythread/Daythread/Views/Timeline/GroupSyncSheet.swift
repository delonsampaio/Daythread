//
//  GroupSyncSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/27/26.
//

import SwiftUI
import SwiftData
import CloudKit

struct GroupSyncSheet: View {
    let trip: Trip

    @Environment(TripStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

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
                        HStack {
                            Image(systemName: "person.2.fill")
                                .foregroundStyle(ThemeTokens.accent)
                            Text("Trip is shared")
                                .foregroundStyle(ThemeTokens.textPrimary)
                            Spacer()
                            Button("Stop Sharing") {
                                cloudKit.stopSharing(trip, modelContext: context)
                            }
                            .foregroundStyle(.red)
                            .font(.caption)
                        }
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
                let members = (trip.members ?? []).filter { !$0.isVirtual }
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
            .navigationTitle("Group Sync")
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
                        title: trip.name
                    )
                    .ignoresSafeArea()
                }
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
            }
        }
    }
}
