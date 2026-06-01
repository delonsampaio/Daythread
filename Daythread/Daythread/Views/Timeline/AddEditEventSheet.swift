//
//  AddEditEventSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData

struct AddEditEventSheet: View {
    let trip: Trip?
    let day: TripDay?
    let vm: TimelineViewModel
    var editingEvent: TripEvent? = nil

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var category: EventCategory = .activity
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date().addingTimeInterval(3600)
    @State private var hasStartTime: Bool = false
    @State private var location: String = ""
    @State private var notes: String = ""
    @State private var isTimeLocked: Bool = false
    @State private var selectedDay: TripDay?
    @State private var showTransitSheet: Bool = false
    @State private var transitDetails: TransitDetails?
    @State private var pendingTransitDetails: TransitDetails?
    @State private var showConflictAlert: Bool = false
    @State private var pendingConflicts: [TripEvent] = []
    /// True once the user has explicitly touched the end-time picker. Before
    /// that, end tracks start automatically (1-hour gap). After, it's theirs.
    @State private var userEditedEndTime: Bool = false

    private var tripDays: [TripDay] {
        trip?.daysArray ?? []
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
                }

                Section("Time") {
                    Toggle("Set a time", isOn: $hasStartTime)
                    if hasStartTime {
                        // UIDatePicker-backed pickers: wheel snaps to 5-minute marks.
                        HStack {
                            Text("Start")
                            Spacer()
                            MinuteIntervalTimePicker(label: "Start", selection: $startTime)
                        }
                        HStack {
                            Text("End")
                            Spacer()
                            MinuteIntervalTimePicker(label: "End", selection: Binding(
                                get: { endTime },
                                set: { userEditedEndTime = true; endTime = $0 }
                            ))
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

                if category.requiresTransitDetails {
                    Section {
                        Button("Edit Transit Details →") {
                            if transitDetails == nil {
                                let td = TransitDetails(context: context)
                                td.id = UUID()
                                transitDetails = td
                                pendingTransitDetails = td
                            }
                            showTransitSheet = true
                        }
                        .foregroundStyle(ThemeTokens.accent)
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
            .sheet(isPresented: $showTransitSheet) {
                if let td = transitDetails {
                    AddEditTransitSheet(details: td)
                }
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
        // Sort chronologically so the alert always leads with the earliest conflict.
        pendingConflicts = conflicts.sorted {
            ($0.startTime ?? .distantFuture) < ($1.startTime ?? .distantFuture)
        }
        showConflictAlert = true
    }

    /// Builds the alert body text, naming every conflicting event.
    private var conflictAlertMessage: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        func describe(_ event: TripEvent) -> String {
            guard let s = event.startTime, let e = event.endTime else { return event.title }
            return "\(event.title) (\(formatter.string(from: s))–\(formatter.string(from: e)))"
        }

        switch pendingConflicts.count {
        case 0:
            return ""
        case 1:
            return "\(describe(pendingConflicts[0])) overlaps on the same day."
        case 2:
            return "\(describe(pendingConflicts[0])) and \(describe(pendingConflicts[1])) overlap on the same day."
        default:
            let first = describe(pendingConflicts[0])
            let rest  = pendingConflicts.count - 1
            return "\(first) and \(rest) other\(rest == 1 ? "" : "s") overlap on the same day."
        }
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
        let targetDay = selectedDay ?? tripDays.first
        if let event = editingEvent {
            event.title = title
            event.category = category
            event.location = location.isEmpty ? nil : location
            event.notes = notes
            event.isTimeLocked = isTimeLocked
            event.startTime = hasStartTime ? startTime : nil
            event.endTime = hasStartTime ? endTime : nil
            if let td = transitDetails { event.transitDetails = td }
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
            // Zone-hopping: link parent before save so CloudKit assigns the
            // record to the correct zone on first persist.
            event.day = targetDay
            if let td = transitDetails { event.transitDetails = td }
            pendingTransitDetails = nil  // committed — don't delete on dismiss
        }
        try? context.save()
        HapticManager.shared.sheetConfirm()
        dismiss()
    }
}
