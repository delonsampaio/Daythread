//
//  ThemeTokens.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI

enum ThemeTokens {
    // Accent (travel blue)
    static let accent = Color(red: 0.0, green: 0.48, blue: 1.0)   // matches SF Blue

    // Pro accent
    static let accentPro = Color(red: 0.608, green: 0.349, blue: 0.714)

    // Semantic surfaces — uses system adaptive colors for Dark Mode
    static let backgroundPrimary = Color(.systemGroupedBackground)
    static let backgroundCard    = Color(.secondarySystemGroupedBackground)

    // Text
    static let textPrimary   = Color.primary
    static let textSecondary = Color.secondary
    static let textMuted     = Color(.tertiaryLabel)

    // Status
    static let warningAmber = Color(red: 0.95, green: 0.61, blue: 0.07)
    static let successGreen = Color(red: 0.20, green: 0.78, blue: 0.35)

    // Tab icons
    static let tabTimeline = "calendar"
    static let tabTrips    = "airplane.departure"
    static let tabVault    = "folder.fill"
    static let tabProfile  = "person.fill"

    // Card style
    static let cardCornerRadius: CGFloat = 16
    static let cardShadow = Shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)

    // Typography
    static let monoFont    = Font.system(.body, design: .monospaced)
    static let monoCaption = Font.system(.caption, design: .monospaced)
}

struct Shadow {
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
