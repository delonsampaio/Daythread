//
//  ScheduleEngine.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/29/26.
//
//  Pure interval-math engine for detecting time conflicts between events.
//  Has no dependency on ViewModels, SwiftUI, or the persistence layer.
//

import Foundation

private extension Date {
    /// Drops seconds and sub-second components so interval math compares at the
    /// minute granularity events are actually authored at.
    var truncatedToMinute: Date {
        Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: self)
        ) ?? self
    }
}

struct ScheduleEngine {
    /// Returns all events in `candidates` whose time window strictly overlaps [startTime, endTime).
    ///
    /// **Rules:**
    /// - Returns `[]` immediately if `startTime >= endTime` (degenerate or inverted window).
    /// - Skips any candidate that lacks either `startTime` or `endTime`.
    /// - Skips the candidate whose `id` matches `excludingID` (the event being saved).
    /// - Overlap is **strict**: events touching at a single boundary point are *not* conflicts.
    ///   e.g. Museum (10:00–12:00) adjacent to Lunch (12:00–13:00) → no conflict.
    ///
    /// - Parameters:
    ///   - startTime: Start of the window being checked.
    ///   - endTime:   End of the window being checked. Must be > `startTime` to produce results.
    ///   - candidates: Events to test against the window (typically `day.events ?? []`).
    ///   - excludingID: ID of the event being edited; that event is excluded from results.
    static func findConflicts(
        startTime: Date,
        endTime: Date,
        among candidates: [TripEvent],
        excludingID: UUID? = nil
    ) -> [TripEvent] {
        // Compare at whole-minute precision. Events are minute-granular (the
        // time picker snaps to 5-minute marks), but legacy rows may carry stray
        // seconds; without truncation two boundary-adjacent events (10–11pm and
        // 11pm–12am) overlap by those seconds and falsely conflict.
        let start = startTime.truncatedToMinute
        let end   = endTime.truncatedToMinute

        // Degenerate window (inverted or zero-duration) → no conflicts possible.
        guard start < end else { return [] }

        return candidates.filter { candidate in
            // Skip the event being edited.
            if let excludingID, candidate.id == excludingID { return false }
            // Both times required on the candidate — untimed events are skipped.
            guard let cStart = candidate.startTime?.truncatedToMinute,
                  let cEnd   = candidate.endTime?.truncatedToMinute else { return false }
            // Strict overlap: [start, end) ∩ [cStart, cEnd) is non-empty iff:
            //   start < cEnd  AND  cStart < end
            return start < cEnd && cStart < end
        }
    }
}
