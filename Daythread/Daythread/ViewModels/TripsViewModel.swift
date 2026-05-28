//
//  TripsViewModel.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import Foundation
import SwiftData
import Observation

@Observable
final class TripsViewModel {

    // MARK: — Trip lifecycle

    @discardableResult
    func createTrip(
        name: String,
        destination: String,
        start: Date,
        end: Date,
        context: ModelContext
    ) -> Trip {
        // Insert parent first, then children — SwiftData relationship tracking
        // is fragile when you set a relationship on an uninserted parent object.
        let trip = Trip(name: name, destination: destination, startDate: start, endDate: end)
        context.insert(trip)

        // Auto-generate TripDay entries (one per calendar day in range).
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        for i in 0...days {
            if let date = Calendar.current.date(byAdding: .day, value: i, to: start) {
                let day = TripDay(date: date, sortOrder: i * 1024)
                context.insert(day)
                day.trip = trip
            }
        }

        try? context.save()
        return trip
    }

    func archiveTrip(_ trip: Trip, context: ModelContext) {
        trip.isArchived = true
        try? context.save()
    }

    func unarchiveTrip(_ trip: Trip, context: ModelContext) {
        trip.isArchived = false
        try? context.save()
    }

    func deleteTrip(_ trip: Trip, context: ModelContext) {
        context.delete(trip)
        try? context.save()
    }

    // MARK: — Edit trip

    func updateTrip(
        _ trip: Trip,
        name: String,
        destination: String,
        start: Date,
        end: Date,
        coverImageData: Data?,
        context: ModelContext
    ) {
        trip.name = name
        trip.destination = destination
        trip.coverImageData = coverImageData

        let cal = Calendar.current
        let datesChanged = !cal.isDate(start, inSameDayAs: trip.startDate) ||
                           !cal.isDate(end,   inSameDayAs: trip.endDate)
        if datesChanged {
            reconcileDays(trip: trip, newStart: start, newEnd: end, context: context)
        }

        trip.startDate = start
        trip.endDate   = end
        try? context.save()
    }

    /// Reconciles TripDay records after a date range change:
    /// - Removes days outside the new range (cascades to their events).
    /// - Adds new TripDay records for dates added to the range.
    /// - Re-sequences sortOrder across all days.
    ///
    /// The caller is responsible for warning the user before calling this
    /// if any removed days contain events (use `eventCountOutsideRange`).
    func reconcileDays(trip: Trip, newStart: Date, newEnd: Date, context: ModelContext) {
        let cal = Calendar.current

        // Build the target date set.
        let span = cal.dateComponents([.day], from: newStart, to: newEnd).day ?? 0
        var targetDates: [Date] = []
        for i in 0...span {
            if let d = cal.date(byAdding: .day, value: i, to: newStart) {
                targetDates.append(cal.startOfDay(for: d))
            }
        }
        let targetDateSet = Set(targetDates)

        let existingDays = (trip.days ?? []).sorted { $0.date < $1.date }
        let existingDateSet = Set(existingDays.map { cal.startOfDay(for: $0.date) })

        // Remove days outside the new range (cascade deletes their events).
        let daysToRemove = existingDays.filter { !targetDateSet.contains(cal.startOfDay(for: $0.date)) }
        daysToRemove.forEach { context.delete($0) }

        // Add days for dates not already covered.
        var newlyAdded: [TripDay] = []
        for date in targetDates where !existingDateSet.contains(date) {
            let day = TripDay(date: date, sortOrder: 0)
            context.insert(day)
            day.trip = trip
            newlyAdded.append(day)
        }

        // Re-sequence sort orders across surviving + newly added days.
        let surviving = existingDays.filter { targetDateSet.contains(cal.startOfDay(for: $0.date)) }
        let allDays = (surviving + newlyAdded).sorted { $0.date < $1.date }
        for (i, day) in allDays.enumerated() { day.sortOrder = i * 1024 }
    }

    /// Returns the total number of events on days that would be removed
    /// if the trip were shortened to [newStart, newEnd]. Used by EditTripSheet
    /// to decide whether to show a destructive-action warning.
    func eventCountOutsideRange(trip: Trip, newStart: Date, newEnd: Date) -> Int {
        let cal = Calendar.current
        return (trip.days ?? [])
            .filter { day in
                let d = cal.startOfDay(for: day.date)
                return d < cal.startOfDay(for: newStart) || d > cal.startOfDay(for: newEnd)
            }
            .reduce(0) { $0 + ($1.events ?? []).count }
    }

    // MARK: — Pre-trip tasks

    func toggleTask(_ task: PreTripTask, context: ModelContext) {
        task.isComplete.toggle()
        try? context.save()
    }

    func addTask(to trip: Trip, title: String, context: ModelContext) {
        // +1024 spacing — consistent with TripEvent fractional indexing.
        let nextOrder = ((trip.preTripTasks ?? []).map(\.sortOrder).max() ?? 0) + 1024
        let task = PreTripTask(title: title, sortOrder: nextOrder)
        context.insert(task)
        task.trip = trip
        try? context.save()
    }

    func deleteTask(_ task: PreTripTask, context: ModelContext) {
        context.delete(task)
        try? context.save()
    }
}
