//
//  ContainerTests.swift
//  DaythreadTests
//
//  Smoke-tests for NSPersistentCloudKitContainer initialization via PersistenceController.
//  These tests catch schema-migration crashes and CloudKit-on-simulator hangs
//  before they reach the device.
//

import XCTest
import CoreData
@testable import Daythread

@MainActor
final class ContainerTests: XCTestCase {

    // MARK: — Schema completeness

    func testInMemoryContainerInitializesWithoutThrowing() {
        XCTAssertNoThrow(PersistenceController(inMemory: true))
    }

    // MARK: — Performance

    /// In-memory store should load well under 1 second.
    func testContainerInitializesInUnderOneSecond() {
        let start = Date()
        _ = PersistenceController(inMemory: true)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(
            elapsed, 1.0,
            "PersistenceController(inMemory:) took \(String(format: "%.3f", elapsed))s — " +
            "possible blocking call leaking in."
        )
    }

    // MARK: — Basic round-trip

    func testCanInsertAndFetchTrip() throws {
        let ctx = PersistenceController(inMemory: true).viewContext

        let trip = Trip(context: ctx)
        trip.id = UUID()
        trip.name = "Tokyo 2026"
        trip.destination = "Japan"
        trip.startDate = .now
        trip.endDate = .now
        trip.gradientSeed = 0
        trip.isArchived = false
        try ctx.save()

        let request: NSFetchRequest<Trip> = Trip.fetchRequest()
        let fetched = try ctx.fetch(request)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Tokyo 2026")
    }

    func testFullObjectGraphSavesWithoutError() throws {
        let ctx = PersistenceController(inMemory: true).viewContext

        let trip = Trip(context: ctx)
        trip.id = UUID(); trip.name = "Full Graph"; trip.destination = "Anywhere"
        trip.startDate = .now; trip.endDate = .now; trip.gradientSeed = 0; trip.isArchived = false

        let day = TripDay(context: ctx)
        day.id = UUID(); day.date = .now; day.sortOrder = 0
        day.trip = trip

        let event = TripEvent(context: ctx)
        event.id = UUID(); event.title = "Lunch"; event.sortOrder = 0
        event.isTimeLocked = false; event.notes = ""; event.category = .restaurant
        event.day = day

        XCTAssertNoThrow(try ctx.save())
    }

    /// Regression for the second-save freeze: without disabling CloudKit on the
    /// in-memory store, the second save hangs waiting for a missing iCloud account.
    func testRepeatedSavesDoNotHang() throws {
        let ctx = PersistenceController(inMemory: true).viewContext

        let trip = Trip(context: ctx)
        trip.id = UUID(); trip.name = "Repeated"; trip.destination = "Anywhere"
        trip.startDate = .now; trip.endDate = .now; trip.gradientSeed = 0; trip.isArchived = false

        let day = TripDay(context: ctx)
        day.id = UUID(); day.date = .now; day.sortOrder = 0
        day.trip = trip
        try ctx.save()

        let start = Date()
        for i in 0..<5 {
            let event = TripEvent(context: ctx)
            event.id = UUID(); event.title = "Event \(i)"; event.sortOrder = i
            event.isTimeLocked = false; event.notes = ""; event.category = .activity
            event.day = day
            try ctx.save()
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 2.0,
            "5 sequential saves took \(String(format: "%.2f", elapsed))s — " +
            "CloudKit mirror may be attached to the in-memory store.")
    }
}
