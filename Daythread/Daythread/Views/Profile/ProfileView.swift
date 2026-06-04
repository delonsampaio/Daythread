//
//  ProfileView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData

struct ProfileView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(TripStore.self) private var store
    @State private var vm = ProfileViewModel()
    @State private var showPaywall = false
    @AppStorage("daythread.userDisplayName") private var displayName = ""

    // Needed to detect whether the user is part of any shared trip.
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "cloudKitShareID != nil")
    ) private var sharedTrips: FetchedResults<Trip>

    /// Show the inline name prompt only to users who are Pro or already in a shared
    /// trip — solo users who never share have no need for a co-editor display name.
    private var shouldShowNamePrompt: Bool {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (store.isPro || !sharedTrips.isEmpty)
    }

    var body: some View {
        NavigationStack {
            List {
                // Inline name field — only shown to Pro users or members of a shared
                // trip who haven't set a name yet. Disappears once a name is entered.
                if shouldShowNamePrompt {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Your name", text: $displayName)
                                .textContentType(.name)
                                .autocorrectionDisabled()
                            Text("Shown to people you share trips with.")
                                .font(.caption)
                                .foregroundStyle(ThemeTokens.textSecondary)
                        }
                        .padding(.vertical, 2)
                    } header: {
                        Text("Your Profile")
                    }
                }

                // Pro status banner
                Section {
                    if store.isPro {
                        HStack(spacing: 12) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(ThemeTokens.accentPro)
                            VStack(alignment: .leading) {
                                Text("Lifetime Pro")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(ThemeTokens.accentPro)
                                Text("All features unlocked")
                                    .font(.caption)
                                    .foregroundStyle(ThemeTokens.textSecondary)
                            }
                        }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                Image(systemName: "lock.open.fill")
                                    .foregroundStyle(ThemeTokens.accentPro)
                                Text("Unlock Lifetime Pro — $9.99")
                                    .foregroundStyle(ThemeTokens.accentPro)
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(ThemeTokens.textMuted)
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Account") {
                    NavigationLink("Settings") { SettingsView() }
                    NavigationLink("Help & FAQ") { HelpView() }
                }

                Section {
                    Button("Restore Purchases") {
                        Task { await vm.restorePurchases(store: store) }
                    }
                    .foregroundStyle(ThemeTokens.textSecondary)
                }

                Section {
                    HStack {
                        Text("Version")
                            .foregroundStyle(ThemeTokens.textSecondary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .foregroundStyle(ThemeTokens.textMuted)
                            .font(ThemeTokens.monoCaption)
                    }
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showPaywall) { ProPaywallView() }
            .task { await vm.syncProStatus(store: store) }
        }
    }
}
