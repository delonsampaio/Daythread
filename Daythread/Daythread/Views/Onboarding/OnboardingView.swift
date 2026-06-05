//  OnboardingView.swift

import SwiftUI
import UserNotifications
import CloudKit

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @AppStorage("daythread.userDisplayName") private var displayName = ""
    @State private var page = 0
    @State private var nameInput = ""
    @FocusState private var keyboardFocused: Bool

    /// Continue is disabled on the name page until the user types something.
    private var canAdvance: Bool {
        guard page == 1 else { return true }
        return !nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $page) {
                OnboardingWelcomePage()
                    .tag(0)
                OnboardingNamePage(nameInput: $nameInput)
                    .tag(1)
                OnboardingNotificationsPage()
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .onChange(of: page) { _, new in
                if new == 2 && nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    withAnimation { page = 1 }
                }
            }

            VStack(spacing: 16) {
                // Page dots
                HStack(spacing: 8) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(i == page ? ThemeTokens.accent : Color(.tertiaryLabel))
                            .frame(width: i == page ? 8 : 6, height: i == page ? 8 : 6)
                            .animation(.spring(duration: 0.25), value: page)
                    }
                }

                // Action button
                Button(action: advance) {
                    Text(page == 2 ? "Let's Go" : "Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(canAdvance ? ThemeTokens.accent : Color(.systemGray4))
                        )
                }
                .disabled(!canAdvance)
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 48)
        }
        .background(ThemeTokens.backgroundPrimary.ignoresSafeArea())
        .task { await prefetchDisplayName() }
    }

    private func prefetchDisplayName() async {
        guard nameInput.isEmpty else { return }

        // 1. iCloud KV store — available instantly after reinstall.
        let kvName = NSUbiquitousKeyValueStore.default.string(forKey: "daythread.userDisplayName") ?? ""
        if !kvName.isEmpty {
            nameInput = kvName
            return
        }

        // 2. CloudKit query — fallback for users who installed before KV store was added.
        do {
            let ckContainer = CKContainer(identifier: "iCloud.com.delonsampaio.daythread")
            let userRecordID = try await ckContainer.userRecordID()
            let uid = userRecordID.recordName
            let pred = NSPredicate(format: "CD_appleUserID == %@", uid)
            let query = CKQuery(recordType: "CD_TripMember", predicate: pred)
            let (matches, _) = try await ckContainer.privateCloudDatabase.records(matching: query, resultsLimit: 1)
            for (_, result) in matches {
                if let record = try? result.get(),
                   let name = record["CD_displayName"] as? String,
                   !name.isEmpty, name != "Traveler" {
                    await MainActor.run { nameInput = name }
                    return
                }
            }
        } catch {
            // Leave blank — user will type their name.
        }
    }

    private func advance() {
        // Dismiss keyboard before any navigation.
        keyboardFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)

        if page < 2 {
            if page == 1 {
                let trimmed = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    displayName = trimmed
                    NSUbiquitousKeyValueStore.default.set(trimmed, forKey: "daythread.userDisplayName")
                }
            }
            withAnimation(.easeInOut(duration: 0.3)) { page += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        let trimmed = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            displayName = trimmed
            NSUbiquitousKeyValueStore.default.set(trimmed, forKey: "daythread.userDisplayName")
        }

        // Fire the system notification prompt now — after the user has read the
        // "Stay in sync" context screen and tapped "Let's Go". No skip button;
        // they can always deny the system prompt or enable it later in Settings.
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        UserDefaults.standard.set(true, forKey: "daythread.onboardingComplete")
        isPresented = false
    }
}
