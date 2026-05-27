//
//  TimelineView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import SwiftData

struct TimelineView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.modelContext) private var context

    // Pragmatic B: @Query stays in the view — CloudKit background syncs auto-refresh
    @Query(sort: \TripDay.sortOrder) private var allDays: [TripDay]
    @Query private var allLodging: [LodgingInfo]

    @State private var vm = TimelineViewModel()
    @State private var showAddEvent = false
    @State private var headerHeight: CGFloat = 0

    private var days: [TripDay] {
        guard let active = store.activeTrip else { return [] }
        return allDays.filter { $0.trip?.id == active.id }
    }

    private var lodging: [LodgingInfo] {
        guard let active = store.activeTrip else { return [] }
        return allLodging.filter { $0.trip?.id == active.id }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Base layer: scrollable timeline
            if store.activeTrip == nil {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        // Spacer to push content below the floating header
                        Color.clear.frame(height: headerHeight)

                        ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                            Section {
                                dayContent(day: day, dayNumber: index + 1)
                            } header: {
                                DayHeaderView(day: day, dayNumber: index + 1)
                            }
                        }
                    }
                    .padding(.bottom, 100)
                }
            }

            // Floating header (top layer)
            VStack(spacing: 0) {
                TripSwitcherStrip()
                if let activeLodging = vm.activeLodging {
                    LodgingBannerView(lodging: activeLodging)
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { headerHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, h in headerHeight = h }
                }
            )

            // FAB (floating action button)
            if store.activeTrip != nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        fabButton
                            .padding(.trailing, 20)
                            .padding(.bottom, 24)
                    }
                }
            }
        }
        // Critical: two-argument .onChange so CloudKit background syncs auto-refresh
        .onChange(of: days) { _, newDays in
            vm.refresh(days: newDays, lodging: lodging)
        }
        .onChange(of: lodging) { _, newLodging in
            vm.refresh(days: days, lodging: newLodging)
        }
        .sheet(isPresented: $showAddEvent) {
            AddEditEventSheet(trip: store.activeTrip, day: days.first, vm: vm)
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .task { vm.refresh(days: days, lodging: lodging) }
    }

    // MARK: — Day content

    @ViewBuilder
    private func dayContent(day: TripDay, dayNumber: Int) -> some View {
        let events = day.events.sorted { $0.sortOrder < $1.sortOrder }
        VStack(spacing: 12) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                TimelineItem(event: event, isLast: index == events.count - 1) {
                    if event.category.requiresTransitDetails, let details = event.transitDetails {
                        TransitCardView(event: event, details: details)
                    } else {
                        EventCardView(event: event)
                    }
                }
                .draggable(event.id.uuidString)
                .contextMenu {
                    if !event.isTimeLocked {
                        Button("Lock Event", systemImage: "lock.fill") {
                            vm.lockEvent(event, context: context)
                        }
                    } else {
                        Button("Unlock Event", systemImage: "lock.open.fill") {
                            vm.lockEvent(event, context: context)
                        }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        vm.deleteEvent(event, context: context)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: — FAB

    private var fabButton: some View {
        Button {
            showAddEvent = true
            HapticManager.shared.fabTap()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(ThemeTokens.accent))
                .cardShadow()
        }
        .glassEffect(.regular, in: Circle())
    }

    // MARK: — Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            TripSwitcherStrip()
            Spacer()
            Image(systemName: "airplane.departure")
                .font(.system(size: 48))
                .foregroundStyle(ThemeTokens.textMuted)
            Text("No trips yet")
                .font(.title2.bold())
                .foregroundStyle(ThemeTokens.textPrimary)
            Text("Create your first trip in the Trips tab.")
                .font(.subheadline)
                .foregroundStyle(ThemeTokens.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }
}
