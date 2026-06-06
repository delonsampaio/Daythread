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
        VStack(spacing: 0) {
            // When focused, anchor content near the top (fixed inset clears the
            // status bar / Dynamic Island). When not focused, center vertically.
            if focused {
                Spacer().frame(height: 60)
            } else {
                Spacer()
            }

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

            // Name field — above the preview so it stays high when the keyboard
            // is open and won't be obscured by the button or keyboard.
            TextField("Tap to enter your name", text: $nameInput)
                .textContentType(.name)
                .autocorrectionDisabled()
                .font(.system(size: 17))
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(ThemeTokens.backgroundCard))
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { focused = false }

            // Preview bubble — below the field so the user can watch it update
            // as they type without the bubble blocking the input area.
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

            Spacer()
            if !focused { Spacer() }
        }
        .animation(.easeInOut(duration: 0.2), value: focused)
        .simultaneousGesture(TapGesture().onEnded { focused = false })
    }
}
