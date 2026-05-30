//
//  GroupSyncSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/27/26.
//

import SwiftUI
import SwiftData

struct GroupSyncSheet: View {
    let trip: Trip

    @Environment(TripStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var cloudKit = CloudKitService()

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
                            Task { await cloudKit.shareTrip(trip, modelContext: context) }
                        } label: {
                            Label("Invite People to This Trip", systemImage: "person.badge.plus")
                                .foregroundStyle(ThemeTokens.accent)
                        }
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
        }
    }
}
