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
        // Degenerate window (inverted or zero-duration) → no conflicts possible.
        guard startTime < endTime else { return [] }

        return candidates.filter { candidate in
            // Skip the event being edited.
            if let excludingID, candidate.id == excludingID { return false }
            // Both times required on the candidate — untimed events are skipped.
            guard let cStart = candidate.startTime,
                  let cEnd   = candidate.endTime else { return false }
            // Strict overlap: [start, end) ∩ [cStart, cEnd) is non-empty iff:
            //   start < cEnd  AND  cStart < end
            return startTime < cEnd && cStart < endTime
        }
    }
}
