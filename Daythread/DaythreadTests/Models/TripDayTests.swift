//
//  TripDayTests.swift
//  DaythreadTests
//

import XCTest
import CoreData
@testable import Daythread

@MainActor
final class TripDayTests: XCTestCase {

    private var ctx: NSManagedObjectContext!

    override func setUp() async throws {
        ctx = PersistenceController(inMemory: true).viewContext
    }

    override func tearDown() async throws {
        ctx = nil
    }

    // Inserts days with sortOrder [2, 0, 1] and verifies the fetch returns them as [0, 1, 2].
    func testDaysReturnedInSortOrderNotInsertionOrder() throws {
        let trip = Trip(context: ctx)
        trip.id = UUID(); trip.name = "Test"; trip.destination = "Anywhere"
        trip.startDate = .now; trip.endDate = .now; trip.gradientSeed = 0; trip.isArchived = false

        let base = Date.now
        let day2 = TripDay(context: ctx); day2.id = UUID(); day2.date = base; day2.sortOrder = 2; day2.trip = trip
        let day0 = TripDay(context: ctx); day0.id = UUID(); day0.date = base.addingTimeInterval(86400); day0.sortOrder = 0; day0.trip = trip
        let day1 = TripDay(context: ctx); day1.id = UUID(); day1.date = base.addingTimeInterval(172800); day1.sortOrder = 1; day1.trip = trip
        try ctx.save()

        let request: NSFetchRequest<TripDay> = TripDay.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TripDay.sortOrder, ascending: true)]
        let fetched = try ctx.fetch(request)

        XCTAssertEqual(fetched.count, 3)
        XCTAssertEqual(fetched.map(\.sortOrder), [0, 1, 2])
    }

    // Verifies that deleting a Trip cascades and removes its TripDays.
    func testDeleteTripCascadesToDays() throws {
        let trip = Trip(context: ctx)
        trip.id = UUID(); trip.name = "Cascade"; trip.destination = "Anywhere"
        trip.startDate = .now; trip.endDate = .now; trip.gradientSeed = 0; trip.isArchived = false

        let d0 = TripDay(context: ctx); d0.id = UUID(); d0.date = .now; d0.sortOrder = 0; d0.trip = trip
        let d1 = TripDay(context: ctx); d1.id = UUID(); d1.date = .now; d1.sortOrder = 1; d1.trip = trip
        try ctx.save()

        ctx.delete(trip)
        try ctx.save()

        let request: NSFetchRequest<TripDay> = TripDay.fetchRequest()
        let remaining = try ctx.fetch(request)
        XCTAssertTrue(remaining.isEmpty)
    }
}
