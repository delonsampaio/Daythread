//
//  TripSwitcherStrip.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import SwiftData

struct TripSwitcherStrip: View {
    @Environment(TripStore.self) private var store
    @Query(
        filter: #Predicate<Trip> { !$0.isArchived },
        sort: \Trip.startDate
    ) private var trips: [Trip]

    var body: some View {
        if trips.isEmpty { EmptyView() } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(trips) { trip in
                        tripChip(trip)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .glassEffect()
        }
    }

    @ViewBuilder
    private func tripChip(_ trip: Trip) -> some View {
        let isActive = store.activeTrip?.id == trip.id
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                store.activeTrip = trip
            }
            HapticManager.shared.tabSwitch()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isActive ? .white : ThemeTokens.textPrimary)
                Text(trip.destination)
                    .font(.system(size: 11))
                    .foregroundStyle(isActive ? .white.opacity(0.8) : ThemeTokens.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isActive {
                    Capsule().fill(ThemeTokens.accent)
                } else {
                    Capsule().fill(ThemeTokens.backgroundCard)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
