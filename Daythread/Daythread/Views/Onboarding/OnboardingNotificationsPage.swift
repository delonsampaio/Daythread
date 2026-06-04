//  OnboardingNotificationsPage.swift

import SwiftUI

struct OnboardingNotificationsPage: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(ThemeTokens.accent)
                .padding(.bottom, 24)

            Text("Stay in sync.")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(ThemeTokens.textPrimary)
                .padding(.bottom, 12)

            Text("Get notified when your event reminders fire or when a co-editor updates the itinerary.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(ThemeTokens.textSecondary)
                .padding(.horizontal, 40)
                .padding(.bottom, 48)

            VStack(spacing: 20) {
                notifRow(icon: "alarm.fill",            color: .orange,          text: "Event reminders at your chosen lead time")
                notifRow(icon: "person.2.fill",         color: ThemeTokens.accent, text: "Alerts when co-editors add or change events")
                notifRow(icon: "clock.badge.checkmark", color: .green,           text: "Departure countdowns for flights and transit")
            }
            .padding(.horizontal, 40)

            Spacer()
            Spacer().frame(height: 160)
        }
        // System notification prompt fires when the user taps "Let's Go" in the
        // parent OnboardingView — not here — so they see this context screen first.
    }

    @ViewBuilder
    private func notifRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)
                .frame(width: 32)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(ThemeTokens.textSecondary)
            Spacer()
        }
    }
}
