//
//  DebugSyncMenu.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/27/26.
//
//  Debug-only toolbar item that simulates three CloudKit sync scenarios so
//  co-editing can be tested without two physical devices.
//  Compiled out entirely in Release builds via #if DEBUG.

#if DEBUG
import SwiftUI
import SwiftData

/// Debug-only menu to simulate CloudKit sync scenarios.
/// Attach to any view with .toolbar { DebugSyncMenuButton() }
struct DebugSyncMenuButton: ToolbarContent {
    @Environment(\.modelContext) private var context
    @Environment(TripStore.self) private var store

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Section("Simulate CloudKit Sync") {
                    Button("Co-editor adds TripEvent") {
                        simulateCoEditorAddsEvent()
                    }
                    Button("Admin deletes TripDay") {
                        simulateAdminDeletesDay()
                    }
                    Button("LodgingInfo.checkIn updated") {
                        simulateLodgingUpdate()
                    }
                }
            } label: {
                Label("Debug Sync", systemImage: "ant.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: — Scenario 1: Co-editor adds a TripEvent

    private func simulateCoEditorAddsEvent() {
        guard let trip = store.activeTrip,
              let day = (trip.days ?? []).sorted(by: { $0.sortOrder < $1.sortOrder }).first else {
            return
        }
        let nextOrder = ((day.events ?? []).map(\.sortOrder).max() ?? -1) + 1
        let event = TripEvent(
            title: "[Sync Test] Co-editor added this",
            category: .museum,
            sortOrder: nextOrder
        )
        event.day = day
        context.insert(event)
        try? context.save()
        print("🔵 DEBUG: Simulated co-editor adding TripEvent '\(event.title)'")
    }

    // MARK: — Scenario 2: Admin deletes a TripDay

    private func simulateAdminDeletesDay() {
        guard let trip = store.activeTrip else { return }
        let sortedDays = (trip.days ?? []).sorted { $0.sortOrder < $1.sortOrder }
        if let lastDay = sortedDays.last, sortedDays.count > 1 {
            context.delete(lastDay)
            try? context.save()
            print("🔵 DEBUG: Simulated admin deleting TripDay (sortOrder \(lastDay.sortOrder))")
        } else {
            print("🔵 DEBUG: Cannot delete day — only one day remains")
        }
    }

    // MARK: — Scenario 3: LodgingInfo.checkIn updated

    private func simulateLodgingUpdate() {
        guard let trip = store.activeTrip,
              let lodging = (trip.lodging ?? []).first else {
            print("🔵 DEBUG: No lodging found on active trip — add lodging first")
            return
        }
        lodging.checkIn = Calendar.current.date(byAdding: .day, value: 1, to: lodging.checkIn) ?? lodging.checkIn
        try? context.save()
        print("🔵 DEBUG: Simulated LodgingInfo.checkIn updated to \(lodging.checkIn)")
    }
}
#endif
