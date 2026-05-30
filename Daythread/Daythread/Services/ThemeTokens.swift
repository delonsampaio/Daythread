//
//  ThemeTokens.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//
//  nonisolated on all statics — Color is Sendable, and these values
//  must be accessible from @Sendable closures (PhotosPicker, Task {}, etc.)
//  under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor.
//

import SwiftUI

enum ThemeTokens {
    // Accent (travel blue)
    nonisolated static let accent = Color(red: 0.0, green: 0.48, blue: 1.0)   // matches SF Blue

    // Pro accent
    nonisolated static let accentPro = Color(red: 0.608, green: 0.349, blue: 0.714)

    // Semantic surfaces — uses system adaptive colors for Dark Mode
    nonisolated static let backgroundPrimary = Color(.systemGroupedBackground)
    nonisolated static let backgroundCard    = Color(.secondarySystemGroupedBackground)

    // Text
    nonisolated static let textPrimary   = Color.primary
    nonisolated static let textSecondary = Color.secondary
    nonisolated static let textMuted     = Color(.tertiaryLabel)

    // Status
    nonisolated static let warningAmber = Color(red: 0.95, green: 0.61, blue: 0.07)
    nonisolated static let successGreen = Color(red: 0.20, green: 0.78, blue: 0.35)

    // Tab icons
    nonisolated static let tabTimeline = "calendar"
    nonisolated static let tabTrips    = "airplane.departure"
    nonisolated static let tabVault    = "folder.fill"
    nonisolated static let tabProfile  = "person.fill"

    // Card style
    nonisolated static let cardCornerRadius: CGFloat = 16

    // Typography
    nonisolated static let monoFont    = Font.system(.body, design: .monospaced)
    nonisolated static let monoCaption = Font.system(.caption, design: .monospaced)
}

extension View {
    /// Applies a shadow that is visible in both light and dark mode.
    ///
    /// Light mode: white cards on a white background have almost no contrast.
    /// A stronger shadow (0.12 opacity) plus a hairline separator border gives
    /// cards their "pill" shape on light backgrounds.
    /// Dark mode: the original subtle shadow (0.04) is fine — contrast already
    /// comes from the card surface being lighter than the page background.
    func cardShadow() -> some View {
        modifier(CardShadowModifier())
    }
}

private struct CardShadowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .shadow(
                color: .black.opacity(colorScheme == .light ? 0.10 : 0.04),
                radius: colorScheme == .light ? 6 : 8,
                x: 0,
                y: colorScheme == .light ? 2 : 4
            )
            .overlay {
                if colorScheme == .light {
                    // Hairline border so cards read as distinct bubbles on
                    // white backgrounds without a heavy visual weight.
                    RoundedRectangle(
                        cornerRadius: ThemeTokens.cardCornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
                }
            }
    }
}
