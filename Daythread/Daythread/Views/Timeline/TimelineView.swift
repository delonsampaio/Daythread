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
        sortDescriptors: [NSSortDescriptor(keyPath: \Trip.startDate, ascending: true)],
        predicate: NSPredicate(format: "isArchived == NO")
    ) private var trips: FetchedResults<Trip>

    /// Deduplicated trip list for the picker — same logic as TripsListView.
    /// Prevents the trip picker from showing the NSPCKC original AND the
    /// shared-store clone during the migration window.
    private var deduplicatedTrips: [Trip] {
        var seen: [UUID: Trip] = [:]
        for trip in trips {
            guard let id = trip.id else { continue }
            if let existing = seen[id] {
                let isClone = trip.objectID.persistentStore?.url?.lastPathComponent == "shared.sqlite"
                if isClone { seen[id] = trip } else { _ = existing }
            } else {
                seen[id] = trip
            }
        }
        return trips.filter { $0.id.map { seen[$0] === $0 } ?? false }
    }

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
            if let trip = store.activeTrip, trip.isAlive {
                // TripTimelineList observes `trip` so adding/removing whole days
                // repaints the list; each day section observes its TripDay so
                // event add/edit/delete/reorder repaints live (the @Query→
                // @FetchRequest migration otherwise loses this auto-refresh).
                TripTimelineList(
                    trip: trip,
                    vm: vm,
                    dragTargetEventID: $dragTargetEventID,
                    endDropTargetDayID: $endDropTargetDayID,
                    swipeOpenEventID: $swipeOpenEventID,
                    editingEvent: $editingEvent
                )
            } else {
                emptyState
            }
        }
        // The timeline uses a custom ScrollView (not a List), so it doesn't get
        // the grouped gray page background automatically. Without this, light
        // mode renders white cards on a white system background with no contrast.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeTokens.backgroundPrimary)
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
        // Screen-level undo toast: pinned to the bottom of the timeline rather
        // than to the day row the event was deleted from.
        .undoDelete(pending: Bindable(vm).pendingEventDelete) { id in
            if let event = try? context.existingObject(with: id) as? TripEvent {
                vm.deleteEvent(event, context: context)
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
            ProPaywallView {
                // After purchase: open GroupSync immediately without a second tap.
                showGroupSync = true
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                tripPickerTitle
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let trip = store.activeTrip {
                    Button {
                        // Pro gate only applies to initiating a share. If the
                        // trip is already shared the user was invited by someone
                        // else — they should reach Group Sync without a paywall.
                        guard store.isPro || trip.cloudKitShareID != nil else {
                            showPaywall = true; return
                        }
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
        }
        } // NavigationStack
    }

    // MARK: — Trip picker title

    @ViewBuilder
    private var tripPickerTitle: some View {
        if deduplicatedTrips.isEmpty {
            Text("Timeline")
                .font(.headline)
        } else {
            Menu {
                ForEach(deduplicatedTrips) { trip in
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
        // Guard against the brief window when the NSPCKC original is deleted
        // during migration Phase 3 — the zombie's @NSManaged Date properties
        // return nil and bridge-crash before store.activeTrip updates to the clone.
        guard trip.isAlive else { return "" }
        let start = trip.startDate.formatted(.dateTime.month(.abbreviated).day())
        let end   = trip.endDate.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
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

// MARK: — Trip day list (observes the trip)

/// Renders the scrolling list of day sections for one trip. Holds the trip as
/// `@ObservedObject` so inserting or deleting a whole TripDay repaints the list.
private struct TripTimelineList: View {
    @ObservedObject var trip: Trip
    let vm: TimelineViewModel
    @Binding var dragTargetEventID: UUID?
    @Binding var endDropTargetDayID: UUID?
    @Binding var swipeOpenEventID: UUID?
    @Binding var editingEvent: TripEvent?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        // When the trip is deleted (locally or via CloudKit sync), its
        // objectWillChange fires and this view re-renders for one pass before the
        // parent swaps to the empty state. Reading the deleted graph would trap, so
        // bail out early.
        if !trip.isAlive {
            Color.clear
        } else {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(Array(trip.daysArray.enumerated()), id: \.element.id) { index, day in
                    DayTimelineSection(
                        day: day,
                        dayNumber: index + 1,
                        vm: vm,
                        dragTargetEventID: $dragTargetEventID,
                        endDropTargetDayID: $endDropTargetDayID,
                        swipeOpenEventID: $swipeOpenEventID,
                        editingEvent: $editingEvent
                    )
                }
            }
            // iPhone: clears FAB (56pt) + tab bar + home indicator.
            // iPad: no tab bar, so use a smaller clearance for the FAB only.
            .padding(.bottom, horizontalSizeClass == .regular ? 80 : 140)
        }
        .refreshable { await PersistenceController.shared.manualRefresh() }
        }
    }
}

// MARK: — Single day section (observes the day)

/// One day's header + event rows. Uses @FetchRequest (not day.eventsArray) so
/// CloudKit-synced inserts from co-editors show up automatically: @FetchRequest
/// observes NSManagedObjectContextObjectsDidChange directly, whereas the
/// relationship NSSet cache on TripDay is NOT updated when mergeChanges inserts
/// a new event as a fault — causing day.eventsArray to return a stale set.
private struct DayTimelineSection: View {
    @ObservedObject var day: TripDay
    let dayNumber: Int
    let vm: TimelineViewModel
    @Binding var dragTargetEventID: UUID?
    @Binding var endDropTargetDayID: UUID?
    @Binding var swipeOpenEventID: UUID?
    @Binding var editingEvent: TripEvent?

    @Environment(\.managedObjectContext) private var context
    @Environment(TripStore.self) private var store

    /// Events for this day, fetched manually from the store rather than via
    /// @FetchRequest. SwiftUI's @FetchRequest does not reliably incorporate
    /// CloudKit-merged inserts (they arrive on a background thread and are dropped),
    /// so co-editor changes only showed after a relaunch's fresh fetch. We replicate
    /// that fresh-fetch behaviour here: reload() runs on appear, on every CloudKit
    /// import (.dayThreadRemoteChangeDidApply), and on any local context change —
    /// always reading current state straight from the store.
    @State private var fetchedEvents: [TripEvent] = []

    var body: some View {
        if !day.isAlive {
            Color.clear
        } else {
        Section {
            dayContent
        } header: {
            let events = fetchedEvents.filter { $0.isAlive }
            let hasOutOfOrder = !vm.outOfOrderEventIDs(in: events).isEmpty
            DayHeaderView(
                day: day,
                dayNumber: dayNumber,
                sortByTimeAction: hasOutOfOrder
                    ? { vm.sortDayByTime(day, context: context) }
                    : nil
            )
        }
        .onAppear { reload() }
        // Remote CloudKit imports post this after merging into the viewContext.
        .onReceive(NotificationCenter.default.publisher(for: .dayThreadRemoteChangeDidApply)) { _ in
            reload()
        }
        // Local edits (add/edit/delete/drag) mutate the viewContext on the main
        // thread; re-fetch so this day stays in sync without @FetchRequest.
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { _ in
            reload()
        }
        }
    }

    /// Fresh fetch of this day's events, sorted by sortOrder — mirrors what a
    /// relaunch does, which is the only thing that reliably reflected co-editor changes.
    private func reload() {
        let request = TripEvent.fetchRequest()
        request.predicate = NSPredicate(format: "day == %@", day)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TripEvent.sortOrder, ascending: true)]
        fetchedEvents = (try? context.fetch(request)) ?? []
    }

    @ViewBuilder
    private var dayContent: some View {
        // Soft-filter: exclude pending-delete and private events the current
        // user isn't the originator of.
        let events = fetchedEvents
            .filter { $0.isAlive }
            .filter { $0.objectID != vm.pendingEventDelete?.id }
            .filter { isVisible($0) }
        let violated = vm.violatedLockIDs(in: events)
        let outOfOrder = vm.outOfOrderEventIDs(in: events)
        VStack(spacing: 12) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                TimelineItem(event: event,
                             isLast: index == events.count - 1,
                             isTimeViolated: event.id.map { violated.contains($0) } ?? false,
                             isOutOfOrder: event.id.map { outOfOrder.contains($0) } ?? false,
                             isShaking: event.id.map { vm.shakingEventIDs.contains($0) } ?? false) {
                    // Swipe left to reveal Edit · Lock · Delete.
                    // Long-press is now exclusively for drag-to-reorder — no gesture conflict.
                    // openID: $swipeOpenEventID ensures at most one panel is open at a time.
                    SwipeRevealCard(
                        id: event.id ?? UUID(),
                        isLocked: event.isTimeLocked,
                        editAction: { editingEvent = event },
                        lockAction: {
                            vm.lockEvent(event, context: context)
                            HapticManager.shared.lockToggle()
                        },
                        deleteAction: {
                            vm.pendingEventDelete = PendingDelete(
                                id: event.objectID,
                                label: event.title.isEmpty ? "Event" : event.title
                            )
                        },
                        openID: $swipeOpenEventID
                    ) {
                        if event.category.requiresTransitDetails, let details = event.transitDetails {
                            TransitCardView(event: event, details: details)
                        } else {
                            EventCardView(event: event)
                        }
                    }
                }
                .draggableWhen(!event.isTimeLocked, payload: event.id?.uuidString ?? "")
                .dropDestination(for: String.self) { items, _ in
                    guard let draggedID = items.first else { return false }
                    let moved = vm.reorderEvent(draggedID: draggedID, before: event,
                                                in: day, context: context,
                                                currentUserID: store.currentUserCloudKitID)
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

            // End-of-day drop zone. Height is generous on empty days (gives a
            // comfortable drag target); compact when events exist so the gap to
            // the next day header stays tight (~24pt total).
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 8)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { items, _ in
                    guard let draggedID = items.first else { return false }
                    let moved = vm.appendEvent(draggedID: draggedID, to: day, context: context,
                                               currentUserID: store.currentUserCloudKitID)
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
        .padding(.top, 4)
    }

    // MARK: — Private event visibility

    /// An event is visible when:
    /// - The trip is not shared (no CloudKit share), OR
    /// - The event is not private, OR
    /// - The current user is the originator, OR
    /// - The current user's ID is in visibleToMemberIDs (Phase 2 subgroup)
    private func isVisible(_ event: TripEvent) -> Bool {
        guard event.day?.trip?.cloudKitShareID != nil else { return true }
        guard event.isPrivate else { return true }
        if isOriginator(event) { return true }
        let myID = store.currentUserCloudKitID ?? ""
        guard !myID.isEmpty, !event.visibleToMemberIDs.isEmpty else { return false }
        return event.visibleToMemberIDs.split(separator: ",").contains(myID[...])
    }

    private func isOriginator(_ event: TripEvent) -> Bool {
        let myID = store.currentUserCloudKitID ?? ""
        if event.addedByAppleUserID.isEmpty || myID.isEmpty {
            // Legacy event or no CloudKit identity — fall back to store ownership.
            return event.day?.trip?.objectID.persistentStore?.url?.lastPathComponent != "shared.sqlite"
        }
        return event.addedByAppleUserID == myID
    }
}

// MARK: — Helpers

private extension View {
    /// Attaches a drag payload when `condition` is true. The `payload` autoclosure
    /// is evaluated by SwiftUI/UIKit exactly when UIDragInteraction requests the
    /// drag item — the precise "lift" moment — so the haptic fires in perfect sync
    /// with no gesture conflicts. Call sites pass a plain String expression unchanged.
    @ViewBuilder
    func draggableWhen(_ condition: Bool, payload: @autoclosure @escaping () -> String) -> some View {
        if condition {
            self.draggable(
                {
                    HapticManager.shared.dragLift()
                    return payload()
                }()
            )
        } else {
            self
        }
    }
}
