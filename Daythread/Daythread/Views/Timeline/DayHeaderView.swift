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
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: day.date)
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
            // WeatherBadgeView slot — renders EmptyView at v1.0 (Tier 2 drop-in)
            WeatherBadgePlaceholder()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect()
    }
}

/// Tier 2 slot — wire WeatherBadgeView here when weather feature ships.
private struct WeatherBadgePlaceholder: View {
    var body: some View { EmptyView() }
}
