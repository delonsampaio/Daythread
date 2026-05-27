//
//  EventCategoryTests.swift
//  DaythreadTests
//
//  Created by Delon Sampaio on 5/26/26.
//

import XCTest
@testable import Daythread

final class EventCategoryTests: XCTestCase {

    func testTransitCasesAreTransit() {
        XCTAssertTrue(EventCategory.flight.isTransit)
        XCTAssertTrue(EventCategory.train.isTransit)
        XCTAssertTrue(EventCategory.bus.isTransit)
        XCTAssertTrue(EventCategory.ferry.isTransit)
    }

    func testNonTransitCasesAreNotTransit() {
        XCTAssertFalse(EventCategory.restaurant.isTransit)
        XCTAssertFalse(EventCategory.museum.isTransit)
        XCTAssertFalse(EventCategory.hotel.isTransit)
    }

    func testTransitRequiresTransitDetails() {
        XCTAssertTrue(EventCategory.flight.requiresTransitDetails)
        XCTAssertTrue(EventCategory.train.requiresTransitDetails)
        XCTAssertFalse(EventCategory.activity.requiresTransitDetails)
    }

    func testAllCasesHaveDisplayName() {
        for category in EventCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty, "\(category) has empty displayName")
        }
    }

    func testAllCasesHaveSystemImage() {
        for category in EventCategory.allCases {
            XCTAssertFalse(category.systemImage.isEmpty, "\(category) has empty systemImage")
        }
    }

    func testRawValueRoundTrip() {
        for category in EventCategory.allCases {
            XCTAssertEqual(EventCategory(rawValue: category.rawValue), category)
        }
    }
}
