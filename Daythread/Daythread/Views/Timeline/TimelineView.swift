//
//  TimelineView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData

struct TimelineView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Trip.startDate)],
        predicate: NSPredicate(format: "isArchived == NO")
    ) private var trips: FetchedResults<Trip>

    private var days: [TripDay] {
        store.activeTrip?.daysArray ?? []
    }

    private var lodging: [LodgingInfo] {
        store.activeTrip?.lodgingArray ?? []
    }

    @State private var vm = TimelineViewModel()
    @State private var showAddEvent = false
    @State private var showGroupSync = false
    @State private var showPaywall = false
    @State private var dragTargetEventID: UUID?
    @State private var endDropTargetDayID: UUID?
    @State private var editingEvent: TripEvent?
    /// ID of the event whose swipe panel is currently open.
    /// Shared across all SwipeRevealCard instances so at most one is open.
    @State private var swipeOpenEventID: UUID?

    var body: some View {
        NavigationStack {
        Group {
            if store.activeTrip == nil {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                            Section {
                                dayContent(day: day, dayNumber: index + 1)
                            } header: {
                                let events = day.eventsArray
                                let hasOutOfOrder = !vm.outOfOrderEventIDs(in: events).isEmpty
                                DayHeaderView(
                                    day: day,
                                    dayNumber: index + 1,
                                    sortByTimeAction: hasOutOfOrder
                                        ? { vm.sortDayByTime(day, context: context) }
                                        : nil
                                )
                            }
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let activeLodging = vm.activeLodging {
                LodgingBannerView(lodging: activeLodging)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if store.activeTrip != nil {
                fabButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 24)
            }
        }
        .onChange(of: lodging) { _, newLodging in
            vm.refresh(days: days, lodging: newLodging)
        }
        .sheet(isPresented: $showAddEvent) {
            AddEditEventSheet(trip: store.activeTrip, day: days.first, vm: vm)
        }
        .sheet(item: $editingEvent) { event in
            AddEditEventSheet(trip: store.activeTrip, day: event.day, vm: vm,
                              editingEvent: event)
        }
        .sheet(isPresented: $showGroupSync) {
            if let trip = store.activeTrip {
                GroupSyncSheet(trip: trip)
            }
        }
        .sheet(isPresented: $showPaywall) {
            ProPaywallView()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                tripPickerTitle
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let trip = store.activeTrip {
                    Button {
                        guard store.isPro else { showPaywall = true; return }
                        showGroupSync = true
                    } label: {
                        Image(systemName: trip.cloudKitShareID != nil ? "person.2.fill" : "person.2")
                            .foregroundStyle(trip.cloudKitShareID != nil
                                             ? ThemeTokens.accent
                                             : ThemeTokens.textSecondary)
                    }
                }
            }
            #if DEBUG
            DebugSyncMenuButton()
            #endif
        }
        .task {
            vm.refresh(days: days, lodging: lodging)
            // Cold-launch restore: if no trip is active, look up the last-used trip by
            // its persisted UUID (previously handled in TripSwitcherStrip.task).
            if store.activeTrip == nil,
               let id = store.storedActiveTripID,
               let match = trips.first(where: { $0.id == id }) {
                store.activeTrip = match
            }
        }
        } // NavigationStack
    }

    // MARK: — Trip picker title

    @ViewBuilder
    private var tripPickerTitle: some View {
        if trips.isEmpty {
            Text("Timeline")
                .font(.headline)
        } else {
            Menu {
                ForEach(trips) { trip in
                    Button {
                        store.activeTrip = trip
                    } label: {
                        if trip.id == store.activeTrip?.id {
                            Label(trip.name, systemImage: "checkmark")
                        } else {
                            Text(trip.name)
                        }
                    }
                }
            } label: {
                VStack(spacing: 1) {
                    // The chevron is an overlay (via alignmentGuide) so it doesn't
                    // widen the name's layout frame — that keeps the date below
                    // centered under the trip name text, not under name + chevron.
                    Text(store.activeTrip?.name ?? "Select Trip")
                        .font(.headline)
                        .foregroundStyle(ThemeTokens.textPrimary)
                        .overlay(alignment: .trailing) {
                            Image(systemName: "chevron.down")
                                .font(.caption2.bold())
                                .foregroundStyle(ThemeTokens.textSecondary)
                                .alignmentGuide(.trailing) { d in d[.leading] - 4 }
                        }
                    if let trip = store.activeTrip {
                        Text(dateRange(for: trip))
                            .font(.caption2)
                            .foregroundStyle(ThemeTokens.textMuted)
                    }
                }
            }
        }
    }

    private func dateRange(for trip: Trip) -> String {
        let start = trip.startDate.formatted(.dateTime.month(.abbreviated).day())
        let end   = trip.endDate.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }

    // MARK: — Day content

    @ViewBuilder
    private func dayContent(day: TripDay, dayNumber: Int) -> some View {
        let events = day.eventsArray
        let violated = vm.violatedLockIDs(in: events)
        let outOfOrder = vm.outOfOrderEventIDs(in: events)
        VStack(spacing: 12) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                TimelineItem(event: event,
                             isLast: index == events.count - 1,
                             isTimeViolated: violated.contains(event.id),
                             isOutOfOrder: outOfOrder.contains(event.id),
                             isShaking: vm.shakingEventIDs.contains(event.id)) {
                    // Swipe left to reveal Edit · Lock · Delete.
                    // Long-press is now exclusively for drag-to-reorder — no gesture conflict.
                    // openID: $swipeOpenEventID ensures at most one panel is open at a time.
                    SwipeRevealCard(
                        id: event.id,
                        isLocked: event.isTimeLocked,
                        editAction: { editingEvent = event },
                        lockAction: {
                            vm.lockEvent(event, context: context)
                            HapticManager.shared.lockToggle()
                        },
                        deleteAction: { vm.deleteEvent(event, context: context) },
                        openID: $swipeOpenEventID
                    ) {
                        if event.category.requiresTransitDetails, let details = event.transitDetails {
                            TransitCardView(event: event, details: details)
                        } else {
                            EventCardView(event: event)
                        }
                    }
                }
                .draggableWhen(!event.isTimeLocked, payload: event.id.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    guard let draggedID = items.first else { return false }
                    let moved = vm.reorderEvent(draggedID: draggedID, before: event,
                                                in: day, context: context)
                    if moved { HapticManager.shared.dragDrop() }
                    return moved
                } isTargeted: { targeted in
                    dragTargetEventID = targeted ? event.id : nil
                }
                .overlay(alignment: .top) {
                    if dragTargetEventID == event.id {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(ThemeTokens.accent)
                            .frame(height: 3)
                    }
                }
            }

            // Explicit end-of-day drop zone — isolated from the per-event drop
            // targets above to avoid SwiftUI hit-testing ambiguity.
            // contentShape(Rectangle()) is required: Color.clear has no hit area
            // by default, so drops on empty days would silently fail without it.
            Color.clear.frame(maxWidth: .infinity, minHeight: 60)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { items, _ in
                    guard let draggedID = items.first else { return false }
                    let moved = vm.appendEvent(draggedID: draggedID, to: day, context: context)
                    if moved { HapticManager.shared.dragDrop() }
                    return moved
                } isTargeted: { targeted in
                    endDropTargetDayID = targeted ? day.id : nil
                }
                .overlay {
                    if endDropTargetDayID == day.id {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(ThemeTokens.accent)
                            .frame(height: 3)
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

// MARK: — Helpers

private extension View {
    @ViewBuilder
    func draggableWhen(_ condition: Bool, payload: String) -> some View {
        if condition {
            self.draggable(payload)
        } else {
            self
        }
    }
}
