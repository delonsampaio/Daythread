//
//  TripStoreMigrator.swift
//  Daythread
//
//  Crash-safe migration of a Trip's full object graph from the NSPCKC private
//  store into the custom-synced shared store. Three-phase:
//    1. cloneGraph  — deep-copy into shared store (this file, Task 3.1)
//    2. upload      — push to custom CloudKit zone (Task 3.2)
//    3. purge       — delete NSPCKC originals ONLY after upload confirmed (Task 3.2)
//
//  SAFETY: NSPCKC deletes propagate only within com.apple.coredata.cloudkit.zone.
//  Records uploaded to our custom Zone-<tripUUID> are in a completely separate
//  zone that NSPCKC does not manage, so purging the NSPCKC copies cannot touch
//  the already-uploaded custom-zone records.
//

import CoreData
import os

@MainActor
final class TripStoreMigrator {
    static let shared = TripStoreMigrator()
    private init() {}

    // MARK: — Phase 1: Clone

    /// Deep-copies the Trip's full object graph into shared.sqlite.
    /// The original NSPCKC-store objects are left untouched.
    /// Returns the clone with migration state .cloned, already saved.
    /// Throws if the shared store cannot be located or the save fails.
    func cloneGraph(_ trip: Trip) throws -> Trip {
        let context = PersistenceController.shared.viewContext
        guard let sharedStore = sharedStore(in: context) else {
            throw MigrationError.sharedStoreNotFound
        }

        // Prefetch the full graph so relationship traversal doesn't fault
        // across actor boundaries or produce partial copies.
        let prefetchRequest = Trip.fetchRequest()
        prefetchRequest.predicate = NSPredicate(format: "self == %@", trip)
        prefetchRequest.relationshipKeyPathsForPrefetching = [
            "days", "days.events", "days.events.transitDetails",
            "documents", "expenses", "lodging", "members", "preTripTasks"
        ]
        prefetchRequest.returnsObjectsAsFaults = false
        _ = try context.fetch(prefetchRequest)

        // Clone Trip.
        let clonedTrip = Trip(context: context)
        context.assign(clonedTrip, to: sharedStore)
        copyTripAttributes(from: trip, to: clonedTrip)
        clonedTrip.ckRecordName = UUID().uuidString   // fresh identity
        clonedTrip.ckSystemFields = nil
        clonedTrip.migration = .cloned

        // Clone TripDay + TripEvent (+ TransitDetails if present).
        for day in trip.daysArray {
            let clonedDay = TripDay(context: context)
            context.assign(clonedDay, to: sharedStore)
            copyDayAttributes(from: day, to: clonedDay)
            clonedDay.ckRecordName = UUID().uuidString
            clonedDay.ckSystemFields = nil
            clonedDay.trip = clonedTrip

            for event in day.eventsArray {
                let clonedEvent = TripEvent(context: context)
                context.assign(clonedEvent, to: sharedStore)
                copyEventAttributes(from: event, to: clonedEvent)
                clonedEvent.ckRecordName = UUID().uuidString
                clonedEvent.ckSystemFields = nil
                clonedEvent.day = clonedDay

                // Clone TransitDetails if one is attached to this event.
                if let td = event.transitDetails {
                    let clonedTD = TransitDetails(context: context)
                    context.assign(clonedTD, to: sharedStore)
                    copyTransitDetailsAttributes(from: td, to: clonedTD)
                    clonedTD.ckRecordName = UUID().uuidString
                    clonedTD.ckSystemFields = nil
                    clonedTD.event = clonedEvent
                }
            }
        }

        // Clone flat direct-Trip children.
        for doc in trip.documentsArray {
            let c = TripDocument(context: context)
            context.assign(c, to: sharedStore)
            copyAllSyncableAttributes(from: doc, to: c)
            c.ckRecordName = UUID().uuidString
            c.ckSystemFields = nil
            c.trip = clonedTrip
        }
        for exp in trip.expensesArray {
            let c = TripExpense(context: context)
            context.assign(c, to: sharedStore)
            copyAllSyncableAttributes(from: exp, to: c)
            c.ckRecordName = UUID().uuidString
            c.ckSystemFields = nil
            c.trip = clonedTrip
        }
        for lodge in trip.lodgingArray {
            let c = LodgingInfo(context: context)
            context.assign(c, to: sharedStore)
            copyAllSyncableAttributes(from: lodge, to: c)
            c.ckRecordName = UUID().uuidString
            c.ckSystemFields = nil
            c.trip = clonedTrip
        }
        for member in trip.membersArray {
            let c = TripMember(context: context)
            context.assign(c, to: sharedStore)
            copyAllSyncableAttributes(from: member, to: c)
            c.ckRecordName = UUID().uuidString
            c.ckSystemFields = nil
            c.trip = clonedTrip
        }
        for task in trip.preTripTasksArray {
            let c = PreTripTask(context: context)
            context.assign(c, to: sharedStore)
            copyAllSyncableAttributes(from: task, to: c)
            c.ckRecordName = UUID().uuidString
            c.ckSystemFields = nil
            c.trip = clonedTrip
        }

        try context.save()
        daythreadLog.log("TripStoreMigrator: cloned trip '\(trip.name, privacy: .public)' → shared store")
        return clonedTrip
    }

    // MARK: — Attribute copiers

    private static let skipped: Set<String> = [
        "ckRecordName", "ckSystemFields", "migrationState",
        "ekEventIdentifier", "hasReminder", "showInCalendar"
    ]

    /// Copies all attributes NOT in the skipped set from `source` to `dest`.
    /// Uses KVC so that new attributes added to the model are automatically
    /// included without updating this method.
    private func copyAllSyncableAttributes(from source: NSManagedObject, to dest: NSManagedObject) {
        for (key, _) in source.entity.attributesByName {
            guard !Self.skipped.contains(key) else { continue }
            dest.setValue(source.value(forKey: key), forKey: key)
        }
    }

    private func copyTripAttributes(from source: Trip, to dest: Trip) {
        dest.id = source.id
        dest.name = source.name
        dest.destination = source.destination
        dest.startDate = source.startDate
        dest.endDate = source.endDate
        dest.createdAt = source.createdAt
        dest.isArchived = source.isArchived
        dest.gradientSeed = source.gradientSeed
        dest.coverImageData = source.coverImageData
        dest.cloudKitShareID = source.cloudKitShareID
        // migrationState is set by the caller after this returns.
    }

    private func copyDayAttributes(from source: TripDay, to dest: TripDay) {
        dest.id = source.id
        dest.date = source.date
        dest.notes = source.notes
        dest.sortOrder = source.sortOrder
    }

    private func copyEventAttributes(from source: TripEvent, to dest: TripEvent) {
        // Copy all syncable attributes generically so new attributes added to the
        // model are automatically included without updating this method.
        for (key, _) in source.entity.attributesByName {
            guard !Self.skipped.contains(key) else { continue }
            dest.setValue(source.value(forKey: key), forKey: key)
        }
    }

    private func copyTransitDetailsAttributes(from source: TransitDetails, to dest: TransitDetails) {
        dest.id = source.id
        dest.carrier = source.carrier
        dest.flightOrTrainNumber = source.flightOrTrainNumber
        dest.pnr = source.pnr
        dest.departureCode = source.departureCode
        dest.arrivalCode = source.arrivalCode
        dest.departureName = source.departureName
        dest.arrivalName = source.arrivalName
        dest.departureTerminal = source.departureTerminal
        dest.arrivalTerminal = source.arrivalTerminal
        dest.departureGate = source.departureGate
        dest.arrivalGate = source.arrivalGate
        dest.seatNumber = source.seatNumber
        dest.baggageClaim = source.baggageClaim
        dest.departureTZIdentifier = source.departureTZIdentifier
        dest.arrivalTZIdentifier = source.arrivalTZIdentifier
        // ckRecordName, ckSystemFields, and event are set by the caller.
    }

    // MARK: — Helpers

    private func sharedStore(in context: NSManagedObjectContext) -> NSPersistentStore? {
        context.persistentStoreCoordinator?.persistentStores
            .first { $0.url?.lastPathComponent == "shared.sqlite" }
    }

    enum MigrationError: Error {
        case sharedStoreNotFound
    }
}
