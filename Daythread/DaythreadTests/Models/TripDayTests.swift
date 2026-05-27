//
//  TripDayTests.swift
//  DaythreadTests
//
//  Created by Delon Sampaio on 5/26/26.
//

import XCTest
import SwiftData
@testable import Daythread

final class TripDayTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Trip.self, TripDay.self, TripEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    // Inserts days with sortOrder [2, 0, 1] and verifies @Query-style sort returns them as [0, 1, 2].
    func testDaysReturnedInSortOrderNotInsertionOrder() throws {
        let trip = Trip(name: "Test", destination: "Anywhere", startDate: .now, endDate: .now)
        context.insert(trip)

        let base = Date.now
        let day2 = TripDay(date: base,                        sortOrder: 2)
        let day0 = TripDay(date: base.addingTimeInterval(86400), sortOrder: 0)
        let day1 = TripDay(date: base.addingTimeInterval(172800), sortOrder: 1)

        trip.days.append(contentsOf: [day2, day0, day1])
        try context.save()

        let descriptor = FetchDescriptor<TripDay>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 3)
        XCTAssertEqual(fetched.map(\.sortOrder), [0, 1, 2])
    }

    // Verifies that deleting a Trip cascades and removes its TripDays.
    func testDeleteTripCascadesToDays() throws {
        let trip = Trip(name: "Cascade", destination: "Anywhere", startDate: .now, endDate: .now)
        context.insert(trip)
        trip.days.append(TripDay(date: .now, sortOrder: 0))
        trip.days.append(TripDay(date: .now, sortOrder: 1))
        try context.save()

        context.delete(trip)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<TripDay>())
        XCTAssertTrue(remaining.isEmpty)
    }
}
