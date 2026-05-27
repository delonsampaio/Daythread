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
        let trip = Trip(name: name, destination: destination, startDate: start, endDate: end)

        // Auto-generate TripDay entries (one per calendar day in range)
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        for i in 0...days {
            if let date = Calendar.current.date(byAdding: .day, value: i, to: start) {
                let day = TripDay(date: date, sortOrder: i)
                day.trip = trip
                context.insert(day)
            }
        }

        context.insert(trip)
        try? context.save()
        return trip
    }

    func archiveTrip(_ trip: Trip, context: ModelContext) {
        trip.isArchived = true
        try? context.save()
    }

    func deleteTrip(_ trip: Trip, context: ModelContext) {
        context.delete(trip)
        try? context.save()
    }

    // MARK: — Pre-trip tasks

    func toggleTask(_ task: PreTripTask, context: ModelContext) {
        task.isComplete.toggle()
        try? context.save()
    }

    func addTask(to trip: Trip, title: String, context: ModelContext) {
        let nextOrder = ((trip.preTripTasks ?? []).map(\.sortOrder).max() ?? -1) + 1
        let task = PreTripTask(title: title, sortOrder: nextOrder)
        task.trip = trip
        context.insert(task)
        try? context.save()
    }

    func deleteTask(_ task: PreTripTask, context: ModelContext) {
        context.delete(task)
        try? context.save()
    }
}
