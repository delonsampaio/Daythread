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
                HStack(spacing: 8) {
                    ForEach(trips) { trip in
                        tripCard(trip)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            // .bar matches the system nav bar material — adapts to dark/light mode
            // and visually merges the strip with the navigation bar above it.
            .background(.bar)
            .overlay(alignment: .bottom) {
                Divider()
            }
            // Cold-launch restore: if the active trip was cleared (e.g. app re-launched),
            // look up the last-used trip by its stored UUID and reselect it automatically.
            .task {
                guard store.activeTrip == nil,
                      let id = store.storedActiveTripID,
                      let match = trips.first(where: { $0.id == id }) else { return }
                store.activeTrip = match
            }
        }
    }

    @ViewBuilder
    private func tripCard(_ trip: Trip) -> some View {
        let isActive = store.activeTrip?.id == trip.id
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                store.activeTrip = trip
            }
            HapticManager.shared.tabSwitch()
        } label: {
            HStack(spacing: 8) {
                // Icon badge
                Image(systemName: "airplane.departure")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isActive ? .white : ThemeTokens.accent)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? .white : ThemeTokens.textPrimary)
                        .lineLimit(1)
                    Text(dateRange(for: trip))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(isActive ? .white.opacity(0.75) : ThemeTokens.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? ThemeTokens.accent : ThemeTokens.backgroundCard)
            }
            .overlay {
                if !isActive {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func dateRange(for trip: Trip) -> String {
        let start = trip.startDate.formatted(.dateTime.month(.abbreviated).day())
        let end   = trip.endDate.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }
}
