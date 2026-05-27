//
//  TimelineItem.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI

/// Wraps every card in the timeline with a left-column time + icon + connector line.
/// Connector height is measured dynamically from the card's GeometryReader.
struct TimelineItem<Content: View>: View {
    let event: TripEvent
    let isLast: Bool
    @ViewBuilder let content: Content

    @State private var cardHeight: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left column: time + icon + connector
            leftColumn

            // Right column: card content
            // onGeometryChange coalesces measurements into one update per layout pass,
            // avoiding the "tried to update multiple times per frame" feedback loop.
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
        }
    }

    private var leftColumn: some View {
        VStack(spacing: 0) {
            // Time label
            if let time = event.startTime {
                Text(TimezoneEngine.displayTime(date: time, in: .current))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .frame(width: 52, alignment: .trailing)
            } else {
                Spacer().frame(width: 52, height: 14)
            }

            // Category icon circle
            ZStack {
                Circle()
                    .fill(event.category.accentColor.opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: event.category.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(event.category.accentColor)
            }

            // Connector line — height matched to card
            if !isLast {
                Rectangle()
                    .fill(Color.quaternaryLabel)
                    .frame(width: 2, height: max(0, cardHeight - 30))
            }
        }
        .frame(width: 52)
    }
}

private extension Color {
    static let quaternaryLabel = Color(uiColor: .quaternaryLabel)
}
