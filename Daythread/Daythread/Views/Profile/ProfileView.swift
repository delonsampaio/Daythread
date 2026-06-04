//
//  ProfileView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI

struct ProfileView: View {
    @Environment(TripStore.self) private var store
    @State private var vm = ProfileViewModel()
    @State private var showPaywall = false
    @AppStorage("daythread.userDisplayName") private var displayName = ""

    var body: some View {
        NavigationStack {
            List {
                // Inline name field — shown whenever the profile name is empty so
                // the user sees it without needing to dig into Settings.
                if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
