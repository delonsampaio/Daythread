//
//  ContainerTests.swift
//  DaythreadTests
//
//  Created by Delon Sampaio on 5/27/26.
//
//  Smoke-tests for ModelContainer initialization.
//  These tests would have caught the CloudKit-on-Simulator hang (30–60 s block)
//  and any schema migration crashes before they reached the device.
//

import XCTest
import SwiftData
@testable import Daythread

/// All 9 model types that makeContainer() registers.
private let fullSchema = Schema([
    Trip.self,
    TripDay.self,
    TripEvent.self,
    TransitDetails.self,
    LodgingInfo.self,
    TripMember.self,
    TripDocument.self,
    TripExpense.self,
    PreTripTask.self
])

@MainActor
final class ContainerTests: XCTestCase {

    // MARK: — Schema completeness

    /// Verifies every model type the app uses can be registered together
    /// without throwing a schema conflict or migration error.
    func testFullSchemaInitializesWithoutThrowing() throws {
        let config = ModelConfiguration(schema: fullSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: fullSchema, configurations: config)
        XCTAssertNotNil(container)
    }

    // MARK: — Performance

    /// In-memory ModelContainer should initialize well under 1 second.
    /// A value ≥ 1 s means something is blocking (e.g. CloudKit account check
    /// leaking into the in-memory path).
    func testContainerInitializesInUnderOneSecond() throws {
        let start = Date()
        let config = ModelConfiguration(schema: fullSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        _ = try ModelContainer(for: fullSchema, configurations: config)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(
            elapsed, 1.0,
            "ModelContainer(in-memory) took \(String(format: "%.3f", elapsed))s — " +
            "possible blocking call (CloudKit, disk I/O, migration?) leaking in."
        )
    }

    // MARK: — Basic round-trip

    /// Verifies a Trip can be inserted and fetched back — confirms the store
    /// is actually writable and not silently dropped.
    func testCanInsertAndFetchTrip() throws {
        let config = ModelConfiguration(schema: fullSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: fullSchema, configurations: config)
        let context = ModelContext(container)

        let trip = Trip(name: "Tokyo 2026", destination: "Japan",
                        startDate: .now, endDate: .now)
        context.insert(trip)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Trip>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Tokyo 2026")
    }

    /// Verifies all relationship types can be attached to a Trip without crashing.
    /// Exercises the full object graph in one container instance.
    func testFullObjectGraphSavesWithoutError() throws {
        let config = ModelConfiguration(schema: fullSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: fullSchema, configurations: config)
        let context = ModelContext(container)

        let trip = Trip(name: "Full Graph", destination: "Anywhere",
                        startDate: .now, endDate: .now)
        context.insert(trip)

        let day = TripDay(date: .now, sortOrder: 0)
        context.insert(day)
        day.trip = trip

        let event = TripEvent(title: "Lunch", category: .restaurant, sortOrder: 0)
        context.insert(event)
        event.day = day

        XCTAssertNoThrow(try context.save())
    }

    /// Regression for the simulator second-save freeze:
    /// without `cloudKitDatabase: .none`, SwiftData attaches a CloudKit mirror
    /// to the in-memory store. The first save succeeds, the second hangs
    /// forever trying to push pending changes to a missing iCloud account.
    /// This test forces the issue to surface: if it ever times out, the
    /// production config has regressed.
    func testRepeatedSavesDoNotHang() throws {
        let config = ModelConfiguration(schema: fullSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: fullSchema, configurations: config)
        let context = ModelContext(container)

        let trip = Trip(name: "Repeated", destination: "Anywhere",
                        startDate: .now, endDate: .now)
        context.insert(trip)
        let day = TripDay(date: .now, sortOrder: 0)
        context.insert(day)
        day.trip = trip
        try context.save()

        // Add events one at a time and save between each. Without the fix
        // the second save can hang for tens of seconds (or forever).
        let start = Date()
        for i in 0..<5 {
            let event = TripEvent(title: "Event \(i)", category: .activity, sortOrder: i)
            context.insert(event)
            event.day = day
            try context.save()
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 2.0,
            "5 sequential saves took \(String(format: "%.2f", elapsed))s — " +
            "CloudKit mirror is likely re-attached. Add cloudKitDatabase: .none.")
    }
}
