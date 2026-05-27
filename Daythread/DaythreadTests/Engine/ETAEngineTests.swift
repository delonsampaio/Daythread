//
//  ETAEngineTests.swift
//  DaythreadTests
//
//  Created by Delon Sampaio on 5/26/26.
//

import XCTest
import CoreLocation
@testable import Daythread

// MARK: — Mock directions provider

struct MockDirectionsProvider: DirectionsProviding {
    let fixedETA: TimeInterval

    func calculateETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> TimeInterval {
        fixedETA
    }
}

struct FailingDirectionsProvider: DirectionsProviding {
    struct ETAError: Error {}
    func calculateETA(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> TimeInterval {
        throw ETAError()
    }
}

// MARK: — Tests

final class ETAEngineTests: XCTestCase {
    let paris  = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
    let louvre = CLLocationCoordinate2D(latitude: 48.8606, longitude: 2.3376)

    func testReturnsETAFromProvider() async throws {
        let provider = MockDirectionsProvider(fixedETA: 720)
        let result = try await ETAEngine.eta(from: paris, to: louvre, provider: provider)
        XCTAssertEqual(result, 720)
    }

    func testFormatsETAAsString() {
        let result = ETAEngine.formatETA(seconds: 720)
        XCTAssertEqual(result, "12m")
    }

    func testFormatsETAHoursAndMinutes() {
        let result = ETAEngine.formatETA(seconds: 5400)
        XCTAssertEqual(result, "1h 30m")
    }

    func testPropagatesProviderError() async {
        let provider = FailingDirectionsProvider()
        do {
            _ = try await ETAEngine.eta(from: paris, to: louvre, provider: provider)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is FailingDirectionsProvider.ETAError)
        }
    }

    func testSameLocationReturnsZero() async throws {
        let provider = MockDirectionsProvider(fixedETA: 0)
        let result = try await ETAEngine.eta(from: paris, to: paris, provider: provider)
        XCTAssertEqual(result, 0)
    }
}
