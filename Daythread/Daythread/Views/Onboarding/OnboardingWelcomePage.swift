//  OnboardingWelcomePage.swift

import SwiftUI

struct OnboardingWelcomePage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 80)

                // App icon area
                Image(systemName: "airplane.departure")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(ThemeTokens.accent)
                    .padding(.bottom, 24)

                Text("Plan the perfect trip,\ntogether.")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ThemeTokens.textPrimary)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 12)

                Text("Build daily itineraries, split expenses, and co-edit in real time with your travel crew.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 56)

                VStack(spacing: 28) {
                    featureRow(
                        icon: "person.2.fill",
                        color: ThemeTokens.accent,
                        title: "Real-time Co-editing",
                        subtitle: "Share trips with friends and family. Changes sync in seconds."
                    )
                    featureRow(
                        icon: "dollarsign.circle.fill",
                        color: .green,
                        title: "Expense Splitting",
                        subtitle: "Log costs, split fairly, and settle up in one tap."
                    )
                    featureRow(
                        icon: "doc.fill",
                        color: .orange,
                        title: "Document Vault",
                        subtitle: "Passports, visas, confirmations — all in one secure place."
                    )
                }
                .padding(.horizontal, 32)

                Spacer().frame(height: 160)
            }
        }
    }

    @ViewBuilder
    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(color)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ThemeTokens.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
            Spacer()
        }
    }
}
