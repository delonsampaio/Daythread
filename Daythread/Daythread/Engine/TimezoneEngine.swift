//
//  TimezoneEngine.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//
//  Pure struct — zero SwiftUI/SwiftData imports.
//  All functions are nonisolated static — safe to call from any context.

import Foundation

struct TimezoneEngine {

    /// Formats `date` as a local time string in the given timezone.
    /// Uses 12h or 24h based on the user's locale.
    /// `Date.FormatStyle` is internally pooled — avoids the cost of `DateFormatter()` alloc per cell.
    nonisolated static func displayTime(date: Date, in timezone: TimeZone) -> String {
        var style: Date.FormatStyle = .dateTime.hour().minute()
        style.timeZone = timezone
        return date.formatted(style)
    }

    /// Returns true if the arrival falls on a later calendar day in the destination
    /// timezone than the departure falls in the origin timezone.
    nonisolated static func overnightArrival(
        depart: Date,
        arrive: Date,
        fromTZ: TimeZone,
        toTZ: TimeZone
    ) -> Bool {
        var depCalendar = Calendar.current
        depCalendar.timeZone = fromTZ
        var arrCalendar = Calendar.current
        arrCalendar.timeZone = toTZ

        let depDay = depCalendar.component(.day, from: depart)
        let arrDay = arrCalendar.component(.day, from: arrive)

        return arrive > depart && arrDay != depDay
    }

    /// Human-readable duration from a seconds value: "1h 30m", "2h", "45m"
    nonisolated static func durationString(seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours   = totalMinutes / 60
        let minutes = totalMinutes % 60
        switch (hours, minutes) {
        case (0, let m): return "\(m)m"
        case (let h, 0): return "\(h)h"
        case (let h, let m): return "\(h)h \(m)m"
        }
    }
}
