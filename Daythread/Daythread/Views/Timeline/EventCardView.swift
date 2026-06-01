//
//  EventCardView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData

struct EventCardView: View {
    // @ObservedObject so edits to the event's fields (title, time, location…)
    // repaint the card live instead of only after a cold relaunch.
    @ObservedObject var event: TripEvent

    var body: some View {
        LiveContent(isDead: !event.isAlive) {
        HStack(spacing: 0) {
            // Left-edge color bar
            Rectangle()
                .fill(event.category.accentColor)
                .frame(width: 4)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: ThemeTokens.cardCornerRadius,
                        bottomLeadingRadius: ThemeTokens.cardCornerRadius
                    )
                )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(event.title)
                        .font(.headline)
                        .foregroundStyle(ThemeTokens.textPrimary)
                    Spacer()
                    if event.isTimeLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(ThemeTokens.warningAmber)
                    }
                }

                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(ThemeTokens.textSecondary)
                        .lineLimit(1)
                }

                if let endTime = event.endTime, let startTime = event.startTime {
                    let duration = TimezoneEngine.durationString(seconds: endTime.timeIntervalSince(startTime))
                    Text(duration)
                        .font(.caption)
                        .foregroundStyle(ThemeTokens.textMuted)
                }

                if !event.notes.isEmpty {
                    Text(event.notes)
                        .font(.caption)
                        .foregroundStyle(ThemeTokens.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
        .background(ThemeTokens.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.cardCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: ThemeTokens.cardCornerRadius))
        .cardShadow()
        }
    }
}
