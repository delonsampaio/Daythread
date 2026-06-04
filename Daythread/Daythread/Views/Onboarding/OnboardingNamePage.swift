//  OnboardingNamePage.swift

import SwiftUI

struct OnboardingNamePage: View {
    @Binding var nameInput: String
    @FocusState private var focused: Bool

    private var previewName: String {
        let t = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "You" : t
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 80)

                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(ThemeTokens.accent)
                    .padding(.bottom, 24)

                Text("What should your\ntravel buddies call you?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ThemeTokens.textPrimary)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 12)

                Text("Your name is shown to people you share trips with.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)

                // Preview bubble
                HStack(spacing: 12) {
                    Circle()
                        .fill(ThemeTokens.accent)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(String(previewName.prefix(2)).uppercased())
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(previewName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ThemeTokens.textPrimary)
                            .animation(.default, value: previewName)
                        Text("Added an event · Just now")
                            .font(.caption)
                            .foregroundStyle(ThemeTokens.textSecondary)
                    }
                    Spacer()
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(ThemeTokens.backgroundCard))
                .padding(.horizontal, 32)
                .padding(.bottom, 32)

                // Name field — user taps to open keyboard, not auto-focused.
                TextField("Tap to enter your name", text: $nameInput)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .font(.system(size: 17))
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(ThemeTokens.backgroundCard))
                    .padding(.horizontal, 32)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { focused = false }

                Spacer().frame(height: 160)
            }
        }
        // Dismiss keyboard when scrolling so the field stays visible.
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { focused = false }
    }
}
