//  OnboardingView.swift

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @AppStorage("daythread.userDisplayName") private var displayName = ""
    @State private var page = 0
    @State private var nameInput = ""
    @State private var notificationsRequested = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $page) {
                OnboardingWelcomePage()
                    .tag(0)
                OnboardingNamePage(nameInput: $nameInput)
                    .tag(1)
                OnboardingNotificationsPage(requested: $notificationsRequested)
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

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
                        .background(RoundedRectangle(cornerRadius: 16).fill(ThemeTokens.accent))
                }
                .padding(.horizontal, 24)

                // Skip on notifications page only
                if page == 2 {
                    Button("Skip for now") { finish() }
                        .font(.subheadline)
                        .foregroundStyle(ThemeTokens.textSecondary)
                }
            }
            .padding(.bottom, 48)
        }
        .background(ThemeTokens.backgroundPrimary.ignoresSafeArea())
    }

    private func advance() {
        if page < 2 {
            if page == 1 {
                let trimmed = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { displayName = trimmed }
            }
            withAnimation(.easeInOut(duration: 0.3)) { page += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        let trimmed = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { displayName = trimmed }
        UserDefaults.standard.set(true, forKey: "daythread.onboardingComplete")
        isPresented = false
    }
}
