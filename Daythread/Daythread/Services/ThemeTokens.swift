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
    nonisolated static let cardShadow = Shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)

    // Typography
    nonisolated static let monoFont    = Font.system(.body, design: .monospaced)
    nonisolated static let monoCaption = Font.system(.caption, design: .monospaced)
}

struct Shadow: Sendable {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func cardShadow() -> some View {
        let s = ThemeTokens.cardShadow
        return self.shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
    }
}
