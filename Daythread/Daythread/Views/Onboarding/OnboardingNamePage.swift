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
        // Not a ScrollView — fixed layout that collapses when the keyboard appears.
        VStack(spacing: 0) {
            Spacer()

            // Icon + headline collapse when typing to keep the field visible.
            if !focused {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(ThemeTokens.accent)
                    .padding(.bottom, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                Text("What should your\ntravel buddies call you?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ThemeTokens.textPrimary)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                Text("Your name is shown to people you share trips with.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 28)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                // Compact header when keyboard is open.
                Text("What should your travel buddies call you?")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ThemeTokens.textPrimary)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)
                    .transition(.opacity)
            }

            // Preview bubble — always visible.
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
            .padding(.bottom, 20)

            // Name field.
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

            // Space above the Continue button — shrinks when keyboard is open.
            Spacer()
            if !focused { Spacer() }
        }
        .animation(.easeInOut(duration: 0.2), value: focused)
        .onTapGesture { focused = false }
        // Let the VStack resize when the keyboard appears rather than being pushed up.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}
