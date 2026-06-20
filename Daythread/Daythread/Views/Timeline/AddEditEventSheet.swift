//
//  AddEditEventSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData
import os

/// Identifiable wrapper so the transit details sheet can present via `.sheet(item:)`
/// instead of `.sheet(isPresented:) + if let`. The latter evaluated `transitDetails`
/// before the newly-created object had propagated, presenting a blank sheet that only
/// filled in on a later (CloudKit-driven) re-render seconds afterward.
private struct TransitDetailsRef: Identifiable {
    let id = UUID()
    let details: TransitDetails
}

struct AddEditEventSheet: View {
    let trip: Trip?
    let day: TripDay?
    let vm: TimelineViewModel
    var editingEvent: TripEvent? = nil

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(TripStore.self) private var store

    @State private var title: String = ""
    @State private var category: EventCategory = .activity
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date().addingTimeInterval(3600)
    @State private var hasStartTime: Bool = false
    @State private var location: String = ""
    @State private var notes: String = ""
    @State private var isTimeLocked: Bool = false
    @State private var selectedDay: TripDay?
    @State private var transitSheetItem: TransitDetailsRef?
    @State private var transitDetails: TransitDetails?
    @State private var pendingTransitDetails: TransitDetails?
    @State private var showConflictAlert: Bool = false
    @State private var pendingConflicts: [TripEvent] = []
    /// Count of conflicting events that are private and not visible to the current
    /// user — reported in the alert as "X other event(s)" without naming them.
    @State private var pendingHiddenConflictCount: Int = 0
    /// True once the user has explicitly touched the end-time picker. Before
    /// that, end tracks start automatically (1-hour gap). After, it's theirs.
    @State private var userEditedEndTime: Bool = false
    @State private var showInCalendar: Bool = true
    @State private var hasReminder: Bool = true
    @State private var isPrivate: Bool = false
    /// IDs of members (besides the originator) who can see this event when private.
    /// Empty = only me. Non-empty = me + selected members.
    @State private var sharedWithMemberIDs: Set<String> = []
    @AppStorage("daythread.notificationsEnabled") private var notificationsEnabled = true

    private var tripDays: [TripDay] {
        trip?.daysArray ?? []
    }

    /// Timezone for the start-time picker: departure city TZ when transit details
    /// are set, otherwise device local. Keeps stored times in sync with the display.
    private var departureTZ: TimeZone {
        guard let id = transitDetails?.departureTZIdentifier, !id.isEmpty,
              let tz = TimeZone(identifier: id) else { return .current }
        return tz
    }

    /// Timezone for the end-time picker: arrival city TZ when transit details are set.
    private var arrivalTZ: TimeZone {
        guard let id = transitDetails?.arrivalTZIdentifier, !id.isEmpty,
              let tz = TimeZone(identifier: id) else { return .current }
        return tz
    }

    /// Trip members other than the current user — shown in the "also visible to" picker.
    private var otherMembers: [TripMember] {
        let myID = store.currentUserCloudKitID ?? ""
        return (trip?.membersArray ?? []).filter { member in
            !member.appleUserID.isEmpty && member.appleUserID != myID
        }
    }

    private var visibilitySummary: String {
        if sharedWithMemberIDs.isEmpty { return "Only you" }
        let names = otherMembers
            .filter { sharedWithMemberIDs.contains($0.appleUserID) }
            .map { $0.displayName.isEmpty ? "Traveler" : $0.displayName }
        return "You + \(names.joined(separator: ", "))"
    }

    /// New events: always can set privacy. Editing: only originator can change it.
    private var canTogglePrivacy: Bool {
        guard let event = editingEvent else { return true }
        let myID = store.currentUserCloudKitID ?? ""
        if event.addedByAppleUserID.isEmpty || myID.isEmpty { return true }
        return event.addedByAppleUserID == myID
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Title", text: $title)

                    NavigationLink {
                        CategoryPickerView(selection: $category)
                    } label: {
                        HStack {
                            Text("Category")
                                .foregroundStyle(ThemeTokens.textPrimary)
                            Spacer()
                            HStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(category.accentColor)
                                        .frame(width: 22, height: 22)
                                    Image(systemName: category.systemImage)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                                Text(category.displayName)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if tripDays.count > 1 {
                        Picker("Day", selection: $selectedDay) {
                            ForEach(Array(tripDays.enumerated()), id: \.element.id) { index, tripDay in
                                Text("Day \(index + 1)").tag(Optional(tripDay))
                            }
                        }
                    }

                    if category.requiresTransitDetails {
                        Button("\(category.displayName) Details →") {
                            let td: TransitDetails
                            if let existing = transitDetails {
                                td = existing
                            } else {
                                td = TransitDetails(context: context)
                                td.id = UUID()
                                // Assign to the SAME store as the trip. A new object with no
                                // relationship defaults into the private store; for a shared
                                // trip the event lands in shared.sqlite (via its day), so an
                                // unassigned TransitDetails creates a cross-store/cross-zone
                                // object graph that poisons NSPCKC export (NSCocoaError 134060)
                                // and halts ALL CloudKit sync until the event is deleted.
                                if let store = (trip ?? day?.trip)?.objectID.persistentStore {
                                    context.assign(td, to: store)
                                }
                                transitDetails = td
                                pendingTransitDetails = td
                            }
                            // .sheet(item:) presents only once the object exists, with the
                            // value handed in directly — no blank-then-fill race.
                            transitSheetItem = TransitDetailsRef(details: td)
                        }
                        .foregroundStyle(ThemeTokens.accent)
                    }
                }

                Section("Time") {
                    Toggle("Set a time", isOn: $hasStartTime)
                    if hasStartTime {
                        // UIDatePicker-backed pickers: wheel snaps to 5-minute marks.
                        // For transit events, use the departure/arrival timezone so
                        // "10:30 AM" is stored as 10:30 AM in the TRANSIT timezone,
                        // matching how TransitCardView displays it.
                        HStack {
                            Text("Start")
                            Spacer()
                            MinuteIntervalTimePicker(
                                label: "Start",
                                selection: $startTime,
                                timeZone: departureTZ
                            )
                        }
                        HStack {
                            Text("End")
                            Spacer()
                            MinuteIntervalTimePicker(
                                label: "End",
                                selection: Binding(
                                    get: { endTime },
                                    set: { userEditedEndTime = true; endTime = $0 }
                                ),
                                timeZone: arrivalTZ
                            )
                        }
                    }

                    Toggle(isOn: $isTimeLocked) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lock Event")
                                .foregroundStyle(
                                    hasStartTime && isTimeLocked
                                    ? ThemeTokens.warningAmber
                                    : ThemeTokens.textPrimary
                                )
                            Text(hasStartTime
                                 ? "Prevents reordering by dragging"
                                 : "Set a time above to enable")
                                .font(.caption)
                                .foregroundStyle(ThemeTokens.textMuted)
                        }
                    }
                    .disabled(!hasStartTime)
                }
                // When time is first enabled on a new event, auto-suggest locking.
                // When time is removed, unlock automatically (no time = no anchor).
                .onChange(of: hasStartTime) { _, newValue in
                    if !newValue {
                        isTimeLocked = false
                        showInCalendar = false
                    } else if editingEvent == nil {
                        isTimeLocked = true
                    }
                }
                // When start changes, shift end by the same delta — but only if
                // the user hasn't manually set an end time. Once they touch the
                // end picker (userEditedEndTime = true) we stop auto-following so
                // their chosen end time is preserved.
                .onChange(of: startTime) { oldStart, newStart in
                    guard !userEditedEndTime else { return }
                    let gap = endTime.timeIntervalSince(oldStart)
                    endTime = newStart.addingTimeInterval(gap > 0 ? gap : 3600)
                }

                Section("Details") {
                    TextField("Location", text: $location)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if hasStartTime {
                    Section {
                        Toggle("Add to Apple Calendar", isOn: $showInCalendar)
                        if notificationsEnabled {
                            Toggle("Remind me", isOn: $hasReminder)
                        }
                    }
                }

                // Visibility: only shown on shared trips; only the originator
                // can change visibility so non-originators can't hide others' events.
                if trip?.cloudKitShareID != nil && canTogglePrivacy {
                    Section {
                        Toggle(isOn: $isPrivate) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Limit visibility")
                                Text(isPrivate ? visibilitySummary : "Everyone in the trip sees this")
                                    .font(.caption)
                                    .foregroundStyle(ThemeTokens.textMuted)
                            }
                        }

                        if isPrivate {
                            let others = otherMembers
                            if others.isEmpty {
                                Text("No other members to share with")
                                    .font(.caption)
                                    .foregroundStyle(ThemeTokens.textMuted)
                            } else {
                                ForEach(others) { member in
                                    let id = member.appleUserID
                                    Button {
                                        if sharedWithMemberIDs.contains(id) {
                                            sharedWithMemberIDs.remove(id)
                                        } else {
                                            sharedWithMemberIDs.insert(id)
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: sharedWithMemberIDs.contains(id)
                                                  ? "checkmark.circle.fill"
                                                  : "circle")
                                                .foregroundStyle(sharedWithMemberIDs.contains(id)
                                                                 ? ThemeTokens.accent
                                                                 : ThemeTokens.textMuted)
                                            Text(member.displayName.isEmpty ? "Traveler" : member.displayName)
                                                .foregroundStyle(ThemeTokens.textPrimary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } header: {
                        if isPrivate {
                            Text("Also visible to")
                        }
                    }
                }

            }
            .navigationTitle(editingEvent == nil ? "Add Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        if let td = pendingTransitDetails {
                            context.delete(td)
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { checkAndSave() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(item: $transitSheetItem) { ref in
                AddEditTransitSheet(details: ref.details, category: category)
            }
        }
        .onAppear { populateIfEditing() }
        .alert("Time Conflict", isPresented: $showConflictAlert) {
            Button("Adjust Time", role: .cancel) { }
            Button("Save Anyway", role: .destructive) { save() }
        } message: {
            Text(conflictAlertMessage)
        }
        .presentationSizing(.page)
    }

    // MARK: — Conflict-aware save

    /// Runs the conflict check before committing. If conflicts exist, shows the
    /// alert so the user can adjust the time or save anyway. No-time events and
    /// inverted windows bypass the check and save directly.
    private func checkAndSave() {
        let targetDay = selectedDay ?? tripDays.first
        guard hasStartTime, endTime > startTime else {
            save(); return
        }
        let conflicts = ScheduleEngine.findConflicts(
            startTime: startTime,
            endTime: endTime,
            among: targetDay?.eventsArray ?? [],
            excludingID: editingEvent?.id
        )
        guard !conflicts.isEmpty else {
            save(); return
        }
        // Split into visible vs hidden so we don't leak private event titles/times
        // to co-editors who aren't allowed to see those events.
        let visible = conflicts.filter { isVisibleToCurrentUser($0) }
        pendingConflicts = visible.sorted {
            ($0.startTime ?? .distantFuture) < ($1.startTime ?? .distantFuture)
        }
        pendingHiddenConflictCount = conflicts.count - visible.count
        showConflictAlert = true
    }

    /// Builds the alert body text. Visible conflicts are named; hidden (private)
    /// conflicts are counted as "X other event(s)" to avoid leaking their details.
    private var conflictAlertMessage: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        func describe(_ event: TripEvent) -> String {
            guard let s = event.startTime, let e = event.endTime else { return event.title }
            return "\(event.title) (\(formatter.string(from: s))–\(formatter.string(from: e)))"
        }

        let hiddenSuffix: String = {
            guard pendingHiddenConflictCount > 0 else { return "" }
            let n = pendingHiddenConflictCount
            return " and \(n) other event\(n == 1 ? "" : "s")"
        }()

        switch pendingConflicts.count {
        case 0 where pendingHiddenConflictCount > 0:
            let n = pendingHiddenConflictCount
            return "\(n) event\(n == 1 ? "" : "s") already \(n == 1 ? "occupies" : "occupy") this time on the same day."
        case 0:
            return ""
        case 1:
            return "\(describe(pendingConflicts[0]))\(hiddenSuffix) overlap\(hiddenSuffix.isEmpty ? "s" : "") on the same day."
        case 2 where hiddenSuffix.isEmpty:
            return "\(describe(pendingConflicts[0])) and \(describe(pendingConflicts[1])) overlap on the same day."
        default:
            let first = describe(pendingConflicts[0])
            let rest  = pendingConflicts.count - 1
            let restText = rest == 1 ? "1 other" : "\(rest) others"
            return "\(first), \(restText)\(hiddenSuffix) overlap on the same day."
        }
    }

    /// Mirrors DayTimelineSection.isVisible — true if the current user can see
    /// this event. Used to filter conflict alerts so private event titles/times
    /// aren't leaked to co-editors who aren't supposed to see them.
    private func isVisibleToCurrentUser(_ event: TripEvent) -> Bool {
        guard trip?.cloudKitShareID != nil else { return true }
        guard event.isPrivate else { return true }
        let myID = store.currentUserCloudKitID ?? ""
        if event.addedByAppleUserID == myID || myID.isEmpty { return true }
        guard !event.visibleToMemberIDs.isEmpty else { return false }
        return event.visibleToMemberIDs.split(separator: ",").contains(myID[...])
    }

    private func populateIfEditing() {
        guard let event = editingEvent else {
            // New event — default to the day passed in from the caller.
            selectedDay = day ?? tripDays.first
            return
        }
        // Read event.day directly so a cross-day drag is always reflected
        // (the `day` parameter may have been captured before the drag).
        selectedDay = event.day ?? day ?? tripDays.first
        title = event.title
        category = event.category
        location = event.location ?? ""
        notes = event.notes
        isTimeLocked = event.isTimeLocked
        if let st = event.startTime { startTime = st; hasStartTime = true }
        if let et = event.endTime { endTime = et; userEditedEndTime = true }
        transitDetails = event.transitDetails
        showInCalendar = event.showInCalendar
        hasReminder    = event.hasReminder
        isPrivate      = event.isPrivate
        if !event.visibleToMemberIDs.isEmpty {
            sharedWithMemberIDs = Set(event.visibleToMemberIDs.split(separator: ",").map(String.init))
        }
    }

    // MARK: — Category picker

    private struct CategoryPickerView: View {
        @Binding var selection: EventCategory
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            List(EventCategory.allCases, id: \.self) { cat in
                Button {
                    selection = cat
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(cat.accentColor)
                                .frame(width: 36, height: 36)
                            Image(systemName: cat.systemImage)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text(cat.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if cat == selection {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(ThemeTokens.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func save() {
        // selectedDay may be a zombie: the TripDay was live when the sheet opened but
        // was deleted while the sheet was open (e.g. owner stopped sharing, zone deleted).
        // A zombie has managedObjectContext == nil, which causes "different contexts" when
        // assigned to event.day. Re-fetch by objectID to get the live viewContext instance,
        // or bail gracefully if the trip itself was deleted.
        let rawTarget = selectedDay ?? tripDays.first
        let targetDay: TripDay?
        if let raw = rawTarget, !raw.isAlive, !raw.objectID.isTemporaryID {
            targetDay = (try? context.existingObject(with: raw.objectID)) as? TripDay
        } else {
            targetDay = rawTarget
        }
        guard targetDay?.isAlive == true else {
            dismiss()
            return
        }
        let savedEvent: TripEvent
        if let event = editingEvent {
            event.title = title
            event.category = category
            event.location = location.isEmpty ? nil : location
            event.notes = notes
            event.isTimeLocked = isTimeLocked
            event.startTime = hasStartTime ? startTime : nil
            event.endTime = hasStartTime ? endTime : nil
            if let td = transitDetails { event.transitDetails = td }
            event.showInCalendar = hasStartTime && showInCalendar
            event.hasReminder    = hasStartTime && hasReminder
            if canTogglePrivacy {
                event.isPrivate = isPrivate
                event.visibleToMemberIDs = isPrivate
                    ? sharedWithMemberIDs.sorted().joined(separator: ",")
                    : ""
            }
            // Apply a day change if the picker was changed (or the event was
            // dragged to a different day before opening edit).
            if event.day?.id != targetDay?.id {
                // Place at end of the target day.
                let nextOrder = ((targetDay?.eventsArray ?? [])
                    .filter { $0.id != event.id }
                    .map(\.sortOrder).max() ?? 0) + 1024
                event.sortOrder = nextOrder
                event.day = targetDay
            }
            savedEvent = event
        } else {
            let nextOrder = ((targetDay?.eventsArray ?? []).map(\.sortOrder).max() ?? 0) + 1024
            let event = TripEvent(context: context)
            event.id = UUID()
            event.title = title
            event.startTime = hasStartTime ? startTime : nil
            event.endTime = hasStartTime ? endTime : nil
            event.location = location.isEmpty ? nil : location
            event.category = category
            event.isTimeLocked = isTimeLocked
            event.sortOrder = nextOrder
            event.notes = notes
            event.showInCalendar      = hasStartTime && showInCalendar
            event.hasReminder         = hasStartTime && hasReminder
            event.isPrivate           = isPrivate
            event.visibleToMemberIDs  = isPrivate
                ? sharedWithMemberIDs.sorted().joined(separator: ",")
                : ""
            event.addedByAppleUserID  = store.currentUserCloudKitID ?? ""
            // Zone-hopping: link parent before save so CloudKit assigns the
            // record to the correct zone on first persist.
            event.day = targetDay
            if let td = transitDetails { event.transitDetails = td }
            pendingTransitDetails = nil  // committed — don't delete on dismiss
            savedEvent = event
        }
        do {
            try context.save()
        } catch {
            daythreadLog.error("AddEditEventSheet save failed: \(error.localizedDescription, privacy: .public)")
        }

        // Calendar + notification sync — fire-and-forget so it doesn't delay dismiss.
        let tripName = trip?.name ?? ""
        let ctx = context
        Task {
            await CalendarService.shared.ensureAuthorized()
            CalendarService.shared.sync(savedEvent, tripName: tripName, context: ctx)
            await NotificationService.shared.requestAuthorization()
            NotificationService.shared.schedule(savedEvent)
        }

        HapticManager.shared.sheetConfirm()
        dismiss()
    }
}
