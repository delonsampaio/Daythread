//
//  DayHeaderView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI

struct DayHeaderView: View {
    let day: TripDay
    let dayNumber: Int

    private var formattedDate: String {
        day.date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Day \(dayNumber)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ThemeTokens.accent)
                    .textCase(.uppercase)
                Text(formattedDate)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ThemeTokens.textPrimary)
            }
            Spacer()
            WeatherBadgePlaceholder()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect()
        .padding(.top, 8)
    }
}

/// Tier 2 slot — wire WeatherBadgeView here when weather feature ships.
private struct WeatherBadgePlaceholder: View {
    var body: some View { EmptyView() }
}
