//
//  AddEditEventSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import SwiftData

struct AddEditEventSheet: View {
    let trip: Trip?
    let day: TripDay?
    let vm: TimelineViewModel
    var editingEvent: TripEvent? = nil

    @Environment(\.modelContext) private var context
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

    private var tripDays: [TripDay] {
        (trip?.days ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Title", text: $title)

                    Picker("Category", selection: $category) {
                        ForEach(EventCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.systemImage).tag(cat)
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
                        DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                    Toggle("Time-locked anchor", isOn: $isTimeLocked)
                        .foregroundStyle(isTimeLocked ? ThemeTokens.accent : ThemeTokens.textPrimary)
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
                                transitDetails = TransitDetails()
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
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
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
    }

    private func populateIfEditing() {
        selectedDay = day ?? tripDays.first
        guard let event = editingEvent else { return }
        title = event.title
        category = event.category
        location = event.location ?? ""
        notes = event.notes
        isTimeLocked = event.isTimeLocked
        if let st = event.startTime { startTime = st; hasStartTime = true }
        if let et = event.endTime { endTime = et }
        transitDetails = event.transitDetails
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
        } else {
            let nextOrder = ((targetDay?.events ?? []).map(\.sortOrder).max() ?? -1) + 1
            let event = TripEvent(
                title: title,
                startTime: hasStartTime ? startTime : nil,
                endTime: hasStartTime ? endTime : nil,
                location: location.isEmpty ? nil : location,
                category: category,
                isTimeLocked: isTimeLocked,
                sortOrder: nextOrder,
                notes: notes
            )
            event.day = targetDay
            if let td = transitDetails { event.transitDetails = td }
            context.insert(event)
        }
        try? context.save()
        HapticManager.shared.sheetConfirm()
        dismiss()
    }
}
