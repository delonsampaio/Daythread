//
//  TimelineItem.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData

/// Wraps every card in the timeline with a left-column time + icon + connector line.
///
/// `isTimeViolated` is true when the event is time-locked but its current position
/// is out of chronological order with its timed neighbours. The left column shows
/// an amber warning badge and the connector is tinted amber to draw attention.
struct TimelineItem<Content: View>: View {
    let event: TripEvent
    let isLast: Bool
    var isTimeViolated: Bool = false
    /// True when this unlocked timed event's visual position contradicts its
    /// startTime relative to surrounding events. Shows amber time text only —
    /// no ring or badge (lighter than the lock-violation treatment).
    var isOutOfOrder: Bool = false
    /// Drives a horizontal shake animation when a drop was refused because this
    /// locked event's time constraint blocked it. Set and cleared by the VM.
    var isShaking: Bool = false

    @ViewBuilder let content: Content

    @State private var shakeAmount: CGFloat = 0

    var body: some View {
        LiveContent(isDead: !event.isAlive) {
        HStack(alignment: .top, spacing: 12) {
            leftColumn
            content
        }
        .modifier(ShakeEffect(animatableData: shakeAmount))
        .onChange(of: isShaking) { _, shaking in
            guard shaking else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                shakeAmount += 1
            }
        }
        }
    }

    // 76 pt accommodates the widest time strings across all locales.
    // Date.FormatStyle uses locale-specific thin/narrow spaces around AM/PM
    // which can make "12:00 PM" render wider than a raw character-count
    // estimate suggests.  76 pt + minimumScaleFactor gives a safe margin.
    private let columnWidth: CGFloat = 76

    private var leftColumn: some View {
        VStack(spacing: 0) {
            // Time label — amber when violated or out of order
            if let time = event.startTime {
                Text(TimezoneEngine.displayTime(date: time, in: .current))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(
                        isTimeViolated || isOutOfOrder
                        ? ThemeTokens.warningAmber
                        : ThemeTokens.textSecondary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
                    .multilineTextAlignment(.center)
                    .frame(width: columnWidth, alignment: .center)
            } else {
                Spacer().frame(width: columnWidth, height: 16)
            }

            // Category icon circle — amber ring when violated
            ZStack {
                Circle()
                    .fill(event.category.accentColor.opacity(isTimeViolated ? 0.08 : 0.15))
                    .frame(width: 36, height: 36)
                    .overlay {
                        if isTimeViolated {
                            Circle()
                                .strokeBorder(ThemeTokens.warningAmber, lineWidth: 1.5)
                        }
                    }
                Image(systemName: event.category.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(event.category.accentColor)
            }
            .frame(width: 36, height: 36)
            // Badge: SF Symbol renders crisply at any size; positioned at
            // bottom-trailing so it doesn't compete with the time label above.
            .overlay(alignment: .bottomTrailing) {
                if isTimeViolated {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ThemeTokens.warningAmber)
                        .background(
                            Circle().fill(Color(uiColor: .systemBackground))
                                .padding(-1)
                        )
                        .offset(x: 8, y: 8)
                }
            }

            // Connector — amber-tinted when violated
            if !isLast {
                Rectangle()
                    .fill(isTimeViolated ? ThemeTokens.warningAmber.opacity(0.35) : Color.connectorLine)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: columnWidth)
    }
}

// MARK: — Shake animation

/// Oscillates the view horizontally when `animatableData` changes.
/// Each increment of `animatableData` by 1 produces one full shake cycle.
private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit: Int = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let x = amount * sin(animatableData * .pi * CGFloat(shakesPerUnit))
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

private extension Color {
    /// Connector thread colour. tertiaryLabel (not quaternary) so the line
    /// stays visible on the light grouped background, while remaining subtle.
    static let connectorLine = Color(uiColor: .tertiaryLabel)
}
