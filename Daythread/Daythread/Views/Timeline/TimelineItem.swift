//
//  TimelineItem.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI

/// Wraps every card in the timeline with a left-column time + icon + connector line.
///
/// `isTimeViolated` is true when the event is time-locked but its current position
/// is out of chronological order with its timed neighbours. The left column shows
/// an amber warning badge and the connector is tinted amber to draw attention.
struct TimelineItem<Content: View>: View {
    let event: TripEvent
    let isLast: Bool
    var isTimeViolated: Bool = false
    /// Drives a horizontal shake animation when a drop was refused because this
    /// locked event's time constraint blocked it. Set and cleared by the VM.
    var isShaking: Bool = false

    @ViewBuilder let content: Content

    @State private var shakeAmount: CGFloat = 0

    var body: some View {
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

    private var leftColumn: some View {
        VStack(spacing: 0) {
            // Time label — amber when violated
            if let time = event.startTime {
                Text(TimezoneEngine.displayTime(date: time, in: .current))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(isTimeViolated ? ThemeTokens.warningAmber : ThemeTokens.textSecondary)
                    .frame(width: 52, alignment: .trailing)
            } else {
                Spacer().frame(width: 52, height: 14)
            }

            // Category icon circle — amber ring when violated
            ZStack {
                Circle()
                    .fill(event.category.accentColor.opacity(isTimeViolated ? 0.08 : 0.15))
                    .frame(width: 30, height: 30)
                    .overlay {
                        if isTimeViolated {
                            Circle()
                                .strokeBorder(ThemeTokens.warningAmber, lineWidth: 1.5)
                        }
                    }
                Image(systemName: event.category.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(event.category.accentColor)
            }
            .frame(width: 30, height: 30)
            // Warning badge sits outside the ZStack so it doesn't affect alignment
            .overlay(alignment: .topTrailing) {
                if isTimeViolated {
                    Circle()
                        .fill(ThemeTokens.warningAmber)
                        .frame(width: 12, height: 12)
                        .overlay {
                            Image(systemName: "exclamationmark")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(.white)
                        }
                        .offset(x: 6, y: -6)
                }
            }

            // Connector — amber-tinted when violated
            if !isLast {
                Rectangle()
                    .fill(isTimeViolated ? ThemeTokens.warningAmber.opacity(0.35) : Color.quaternaryLabel)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 52)
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
    static let quaternaryLabel = Color(uiColor: .quaternaryLabel)
}
