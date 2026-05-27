//
//  TimezoneEngineTests.swift
//  DaythreadTests
//
//  Created by Delon Sampaio on 5/26/26.
//

import XCTest
@testable import Daythread

final class TimezoneEngineTests: XCTestCase {

    // MARK: — displayTime

    func testDisplayTimeFormatsCorrectly() throws {
        let paris = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        var components = DateComponents()
        components.year = 2026; components.month = 6; components.day = 3
        components.hour = 14; components.minute = 30; components.timeZone = paris
        let date = try XCTUnwrap(Calendar.current.date(from: components))

        let result = TimezoneEngine.displayTime(date: date, in: paris)
        XCTAssertFalse(result.isEmpty)
    }

    func testDisplayTimeRespectsTZ() throws {
        let paris = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        let nyc   = try XCTUnwrap(TimeZone(identifier: "America/New_York"))

        var components = DateComponents()
        components.year = 2026; components.month = 6; components.day = 3
        components.hour = 14; components.minute = 0; components.timeZone = paris
        let date = try XCTUnwrap(Calendar.current.date(from: components))

        let parisDisplay = TimezoneEngine.displayTime(date: date, in: paris)
        let nycDisplay   = TimezoneEngine.displayTime(date: date, in: nyc)
        // Paris is UTC+2 in summer, NYC is UTC-4 — they must differ
        XCTAssertNotEqual(parisDisplay, nycDisplay)
    }

    // MARK: — overnightArrival

    func testOvernightFlightParisToBangkok() throws {
        let paris   = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        let bangkok = try XCTUnwrap(TimeZone(identifier: "Asia/Bangkok"))

        var depComp = DateComponents()
        depComp.year = 2026; depComp.month = 6; depComp.day = 3
        depComp.hour = 23; depComp.minute = 45; depComp.timeZone = paris
        let depart = try XCTUnwrap(Calendar.current.date(from: depComp))

        var arrComp = DateComponents()
        arrComp.year = 2026; arrComp.month = 6; arrComp.day = 4
        arrComp.hour = 17; arrComp.minute = 15; arrComp.timeZone = bangkok
        let arrive = try XCTUnwrap(Calendar.current.date(from: arrComp))

        XCTAssertTrue(TimezoneEngine.overnightArrival(
            depart: depart, arrive: arrive, fromTZ: paris, toTZ: bangkok))
    }

    func testSameDayFlightIsNotOvernight() throws {
        let london = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let madrid = try XCTUnwrap(TimeZone(identifier: "Europe/Madrid"))

        var depComp = DateComponents()
        depComp.year = 2026; depComp.month = 6; depComp.day = 3
        depComp.hour = 9; depComp.minute = 0; depComp.timeZone = london
        let depart = try XCTUnwrap(Calendar.current.date(from: depComp))

        var arrComp = DateComponents()
        arrComp.year = 2026; arrComp.month = 6; arrComp.day = 3
        arrComp.hour = 12; arrComp.minute = 30; arrComp.timeZone = madrid
        let arrive = try XCTUnwrap(Calendar.current.date(from: arrComp))

        XCTAssertFalse(TimezoneEngine.overnightArrival(
            depart: depart, arrive: arrive, fromTZ: london, toTZ: madrid))
    }

    func testOvernightFlightParisToNYC() throws {
        let paris = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        let nyc   = try XCTUnwrap(TimeZone(identifier: "America/New_York"))

        var depComp = DateComponents()
        depComp.year = 2026; depComp.month = 6; depComp.day = 3
        depComp.hour = 23; depComp.minute = 45; depComp.timeZone = paris
        let depart = try XCTUnwrap(Calendar.current.date(from: depComp))

        // Arrives NYC June 4 at 01:45 NYC time
        var arrComp = DateComponents()
        arrComp.year = 2026; arrComp.month = 6; arrComp.day = 4
        arrComp.hour = 1; arrComp.minute = 45; arrComp.timeZone = nyc
        let arrive = try XCTUnwrap(Calendar.current.date(from: arrComp))

        XCTAssertTrue(TimezoneEngine.overnightArrival(
            depart: depart, arrive: arrive, fromTZ: paris, toTZ: nyc))
    }

    // MARK: — durationString

    func testDurationStringHoursAndMinutes() {
        XCTAssertEqual(TimezoneEngine.durationString(seconds: 5400), "1h 30m")
    }

    func testDurationStringHoursOnly() {
        XCTAssertEqual(TimezoneEngine.durationString(seconds: 7200), "2h")
    }

    func testDurationStringMinutesOnly() {
        XCTAssertEqual(TimezoneEngine.durationString(seconds: 1800), "30m")
    }
}
