//
//  TripCardView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData

struct TripCardView: View {
    @ObservedObject var trip: Trip

    private var dateRangeLabel: String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: trip.startDate, to: trip.endDate)
    }

    private var durationLabel: String {
        let days = Calendar.current.dateComponents([.day], from: trip.startDate, to: trip.endDate).day ?? 0
        return "\(days + 1) days"
    }

    var body: some View {
        LiveContent(isDead: !trip.isAlive) {
        VStack(alignment: .leading, spacing: 0) {
            // Cover image
            ZStack(alignment: .bottomLeading) {
                if let data = trip.coverImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: gradientColors(for: trip.gradientSeed),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 120)
                }

                HStack(alignment: .bottom) {
                    Text(durationLabel)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassEffect(.regular, in: Capsule())
                    Spacer()
                    let coEditors = trip.membersArray.filter { !$0.isVirtual }
                    if !coEditors.isEmpty {
                        MemberAvatarStack(members: coEditors)
                    }
                }
                .padding(10)
            }
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: ThemeTokens.cardCornerRadius,
                topTrailingRadius: ThemeTokens.cardCornerRadius
            ))

            // Trip info
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ThemeTokens.textPrimary)
                Label(trip.destination, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(ThemeTokens.textSecondary)
                Text(dateRangeLabel)
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.textMuted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ThemeTokens.backgroundCard)
            .clipShape(UnevenRoundedRectangle(
                bottomLeadingRadius: ThemeTokens.cardCornerRadius,
                bottomTrailingRadius: ThemeTokens.cardCornerRadius
            ))
        }
        .cardShadow()
        }
    }

    private func gradientColors(for seed: Int) -> [Color] {
        let palettes: [[Color]] = [
            [.blue, .purple], [.orange, .pink], [.teal, .blue],
            [.green, .teal], [.indigo, .blue], [.mint, .green]
        ]
        let index = abs(seed) % palettes.count
        return palettes[index]
    }
}
