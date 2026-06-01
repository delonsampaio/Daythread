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
import CoreData

/// Debug-only menu to simulate CloudKit sync scenarios.
/// Attach to any view with .toolbar { DebugSyncMenuButton() }
struct DebugSyncMenuButton: ToolbarContent {
    @Environment(\.managedObjectContext) private var context
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
                Section("Schema") {
                    Button("Init CloudKit Schema (run once)") {
                        PersistenceController.shared.initializeCloudKitSchemaIfNeeded()
                    }
                }
                Section("Members") {
                    Button("Add Test Members (×4)") {
                        addTestMembers()
                    }
                    Button("Remove Test Members", role: .destructive) {
                        removeTestMembers()
                    }
                }
                Section("Pro") {
                    if store.isPro {
                        Button("Reset Pro (lock + re-test purchase)", role: .destructive) {
                            store.isPro = false
                            print("🔵 DEBUG: Pro reset — isPro = false")
                        }
                    } else {
                        Button("Grant Pro (unlock locally)") {
                            store.isPro = true
                            print("🔵 DEBUG: Pro granted — isPro = true")
                        }
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
              let day = trip.daysArray.first else {
            return
        }
        let nextOrder = (day.eventsArray.map(\.sortOrder).max() ?? -1) + 1
        let event = TripEvent(context: context)
        event.id = UUID()
        event.title = "[Sync Test] Co-editor added this"
        event.category = .museum
        event.sortOrder = nextOrder
        event.day = day
        try? context.save()
        print("🔵 DEBUG: Simulated co-editor adding TripEvent '\(event.title)'")
    }

    // MARK: — Scenario 2: Admin deletes a TripDay

    private func simulateAdminDeletesDay() {
        guard let trip = store.activeTrip else { return }
        let sortedDays = trip.daysArray
        if let lastDay = sortedDays.last, sortedDays.count > 1 {
            context.delete(lastDay)
            try? context.save()
            print("🔵 DEBUG: Simulated admin deleting TripDay (sortOrder \(lastDay.sortOrder))")
        } else {
            print("🔵 DEBUG: Cannot delete day — only one day remains")
        }
    }

    // MARK: — Members: add / remove test co-editors

    private static let testNames = ["Alice Baker", "Carlos Dean", "Eva Foster", "Greg Hughes"]

    private func addTestMembers() {
        guard let trip = store.activeTrip else {
            print("🔵 DEBUG: No active trip — select a trip first")
            return
        }
        for (index, name) in Self.testNames.enumerated() {
            let member = TripMember(context: context)
            member.id = UUID()
            member.appleUserID = "debug-member-\(index + 1)"
            member.displayName = name
            member.roleRaw = "editor"
            member.joinedAt = Date()
            member.trip = trip
        }
        try? context.save()
        print("🔵 DEBUG: Added \(Self.testNames.count) test members to '\(trip.name)'")
    }

    private func removeTestMembers() {
        let request = TripMember.fetchRequest()
        request.predicate = NSPredicate(format: "appleUserID BEGINSWITH 'debug-member-'")
        let members = (try? context.fetch(request)) ?? []
        members.forEach { context.delete($0) }
        try? context.save()
        print("🔵 DEBUG: Removed \(members.count) test member(s)")
    }

    // MARK: — Scenario 3: LodgingInfo.checkIn updated

    private func simulateLodgingUpdate() {
        guard let trip = store.activeTrip,
              let lodging = trip.lodgingArray.first else {
            print("🔵 DEBUG: No lodging found on active trip — add lodging first")
            return
        }
        lodging.checkIn = Calendar.current.date(byAdding: .day, value: 1, to: lodging.checkIn) ?? lodging.checkIn
        try? context.save()
        print("🔵 DEBUG: Simulated LodgingInfo.checkIn updated to \(lodging.checkIn)")
    }
}
#endif
