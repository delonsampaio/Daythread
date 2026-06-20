//
//  TripsViewModel.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import CloudKit
import CoreData
import Foundation
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
        context: NSManagedObjectContext
    ) -> Trip {
        let trip = Trip(context: context)
        trip.id = UUID()
        trip.name = name
        trip.destination = destination
        trip.startDate = start
        trip.endDate = end
        trip.createdAt = Date()
        trip.gradientSeed = Int.random(in: 0..<1_000_000)

        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        for i in 0...days {
            if let date = Calendar.current.date(byAdding: .day, value: i, to: start) {
                let day = TripDay(context: context)
                day.id = UUID()
                day.date = date
                day.sortOrder = i * 1024
                day.trip = trip
            }
        }

        try? context.save()
        return trip
    }

    func archiveTrip(_ trip: Trip, context: NSManagedObjectContext) {
        trip.isArchived = true
        try? context.save()
    }

    func unarchiveTrip(_ trip: Trip, context: NSManagedObjectContext) {
        trip.isArchived = false
        try? context.save()
    }

    @MainActor
    func deleteTrip(_ trip: Trip, context: NSManagedObjectContext) {
        // Remove calendar entries before deleting so ekEventIdentifiers are still accessible.
        CalendarService.shared.removeAllEvents(for: trip)
        // Delete the CloudKit zone so participants are notified and the zone
        // doesn't become permanently orphaned in the owner's private database.
        if trip.cloudKitShareID != nil, let tripID = trip.id {
            let sharing = SharedZoneSharing()
            Task { try? await sharing.deleteZone(forTripID: tripID) }
        }
        // Delete all copies with the same id (NSPCKC re-import + shared-store clone).
        if let tripID = trip.id {
            let request = Trip.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", tripID as CVarArg)
            let all = (try? context.fetch(request)) ?? []
            all.forEach { context.delete($0) }
        } else {
            context.delete(trip)
        }
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
        context: NSManagedObjectContext
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

    func reconcileDays(trip: Trip, newStart: Date, newEnd: Date, context: NSManagedObjectContext) {
        let cal = Calendar.current

        let span = cal.dateComponents([.day], from: newStart, to: newEnd).day ?? 0
        var targetDates: [Date] = []
        for i in 0...span {
            if let d = cal.date(byAdding: .day, value: i, to: newStart) {
                targetDates.append(cal.startOfDay(for: d))
            }
        }
        let targetDateSet = Set(targetDates)

        let existingDays = trip.daysArray.sorted { $0.date < $1.date }
        let existingDateSet = Set(existingDays.map { cal.startOfDay(for: $0.date) })

        let daysToRemove = existingDays.filter { !targetDateSet.contains(cal.startOfDay(for: $0.date)) }
        daysToRemove.forEach { context.delete($0) }

        var newlyAdded: [TripDay] = []
        for date in targetDates where !existingDateSet.contains(date) {
            let day = TripDay(context: context)
            day.id = UUID()
            day.date = date
            day.sortOrder = 0
            day.trip = trip
            newlyAdded.append(day)
        }

        let surviving = existingDays.filter { targetDateSet.contains(cal.startOfDay(for: $0.date)) }
        let allDays = (surviving + newlyAdded).sorted { $0.date < $1.date }
        for (i, day) in allDays.enumerated() { day.sortOrder = i * 1024 }
    }

    func eventCountOutsideRange(trip: Trip, newStart: Date, newEnd: Date) -> Int {
        let cal = Calendar.current
        return trip.daysArray
            .filter { day in
                let d = cal.startOfDay(for: day.date)
                return d < cal.startOfDay(for: newStart) || d > cal.startOfDay(for: newEnd)
            }
            .reduce(0) { $0 + $1.eventsArray.count }
    }

    // MARK: — Pre-trip tasks

    func toggleTask(_ task: PreTripTask, context: NSManagedObjectContext) {
        task.isComplete.toggle()
        try? context.save()
    }

    func addTask(to trip: Trip, title: String, context: NSManagedObjectContext) {
        let nextOrder = (trip.preTripTasksArray.map(\.sortOrder).max() ?? 0) + 1024
        let task = PreTripTask(context: context)
        task.id = UUID()
        task.title = title
        task.sortOrder = nextOrder
        task.trip = trip
        try? context.save()
    }

    func deleteTask(_ task: PreTripTask, context: NSManagedObjectContext) {
        context.delete(task)
        try? context.save()
    }
}
