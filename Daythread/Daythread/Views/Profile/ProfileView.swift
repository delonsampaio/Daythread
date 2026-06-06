//
//  ProfileView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData
import PhotosUI

struct ProfileView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(TripStore.self) private var store
    @Environment(AppleSignInService.self) private var appleSignIn
    @State private var vm = ProfileViewModel()
    @State private var showPaywall = false
    @State private var versionTapCount = 0
    @State private var showBetaProToggle = false
    @AppStorage("daythread.userDisplayName") private var displayName = ""

    // Avatar — stored locally in UserDefaults as a compressed JPEG thumbnail.
    @State private var avatarData: Data? = UserDefaults.standard.data(forKey: "daythread.userAvatarData")
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var showAvatarPicker = false

    // Needed to detect whether the user is part of any shared trip.
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "cloudKitShareID != nil")
    ) private var sharedTrips: FetchedResults<Trip>

    /// Show the inline name prompt to Pro or shared-trip users who have no name.
    /// Remains visible even when SIWA is linked — Apple only delivers the name on
    /// the very first sign-in, so a reinstalled user can be linked but nameless.
    private var shouldShowNamePrompt: Bool {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (store.isPro || !sharedTrips.isEmpty)
    }

    var body: some View {
        @Bindable var appleSignIn = appleSignIn
        let linkedEmail = appleSignIn.linkedEmail
        NavigationStack {
            List {

                // MARK: — Avatar + Identity header
                Section {
                    HStack(spacing: 16) {
                        // Button label is @MainActor so it can reference @State/@AppStorage.
                        // .photosPicker(isPresented:) avoids the @Sendable closure restriction
                        // that PhotosPicker's content label has in Swift 6.
                        Button { showAvatarPicker = true } label: {
                            AvatarCircle(avatarData: avatarData, displayName: displayName)
                                .frame(width: 64, height: 64)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "pencil.circle.fill")
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(ThemeTokens.accent)
                                        .font(.system(size: 20))
                                        .background(Circle().fill(ThemeTokens.backgroundPrimary).padding(2))
                                }
                        }
                        .buttonStyle(.plain)
                        .photosPicker(isPresented: $showAvatarPicker, selection: $avatarPickerItem, matching: .images)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName.isEmpty ? "Set your name" : displayName)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(displayName.isEmpty ? ThemeTokens.textSecondary : ThemeTokens.textPrimary)
                            if let email = linkedEmail {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(ThemeTokens.textSecondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: avatarPickerItem) { _, item in
                    Task {
                        guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                        let compressed = UIImage(data: data)
                            .flatMap { $0.jpegData(compressionQuality: 0.7) } ?? data
                        avatarData = compressed
                        UserDefaults.standard.set(compressed, forKey: "daythread.userAvatarData")
                    }
                }

                // MARK: — Inline name field (pro / shared users without a name)
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

                // MARK: — Pro status banner
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
                                Text("Unlock Lifetime Pro — $4.99")
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

                // MARK: — Account
                Section("Account") {
                    appleIDRow
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
                    .onTapGesture {
                        versionTapCount += 1
                        if versionTapCount >= 5 {
                            versionTapCount = 0
                            showBetaProToggle = true
                        }
                    }
                }

                if showBetaProToggle {
                    Section {
                        if store.isPro {
                            Button("Revoke Pro (beta)", role: .destructive) {
                                UserDefaults.standard.set(true, forKey: "daythread.betaProRevoked")
                                store.isPro = false
                            }
                        } else {
                            Button("Grant Pro (beta)") {
                                UserDefaults.standard.set(false, forKey: "daythread.betaProRevoked")
                                store.isPro = true
                            }
                            .foregroundStyle(ThemeTokens.accentPro)
                        }
                    } header: {
                        Text("Beta Testing")
                    } footer: {
                        Text("Tap version 5× again to dismiss.")
                    }
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showPaywall) { ProPaywallView() }
            .task { await vm.syncProStatus(store: store) }
            .alert(
                "Sign In Error",
                isPresented: Binding(get: { appleSignIn.errorMessage != nil },
                                     set: { if !$0 { appleSignIn.errorMessage = nil } }),
                actions: { Button("OK") { appleSignIn.errorMessage = nil } },
                message: { Text(appleSignIn.errorMessage ?? "") }
            )
        }
    }

    // MARK: — Apple ID row

    @ViewBuilder
    private var appleIDRow: some View {
        switch appleSignIn.credentialState {
        case .unknown:
            HStack {
                Image(systemName: "apple.logo")
                    .foregroundStyle(ThemeTokens.textSecondary)
                Text("Apple ID")
                    .foregroundStyle(ThemeTokens.textSecondary)
                Spacer()
                ProgressView()
            }

        case .signedIn:
            HStack {
                Image(systemName: "apple.logo")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple ID")
                        .font(.system(size: 15, weight: .medium))
                    if let email = appleSignIn.linkedEmail {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(ThemeTokens.textSecondary)
                    }
                }
                Spacer()
                Button("Disconnect") {
                    appleSignIn.signOut()
                }
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
                .buttonStyle(.plain)
            }

        case .signedOut, .notFound:
            DaythreadSignInWithAppleButton()
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }
}

// Separate struct so it can be used inside PhotosPicker's @Sendable label closure
// without triggering a main-actor isolation error.
private struct AvatarCircle: View {
    let avatarData: Data?
    let displayName: String

    var body: some View {
        if let data = avatarData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            let initials = displayName
                .split(separator: " ")
                .prefix(2)
                .compactMap { $0.first.map { String($0) } }
                .joined()
                .uppercased()
            Circle()
                .fill(ThemeTokens.accent)
                .overlay(
                    Text(initials.isEmpty ? "?" : initials)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
    }
}
