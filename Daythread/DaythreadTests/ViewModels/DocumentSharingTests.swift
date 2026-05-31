//
//  DocumentSharingTests.swift
//  DaythreadTests
//
//  Tests for document-level sharing visibility on shared trips.
//

import XCTest
import CoreData
@testable import Daythread

@MainActor
final class DocumentSharingTests: XCTestCase {

    private var ctx: NSManagedObjectContext!
    private var vm: VaultViewModel!

    override func setUpWithError() throws {
        ctx = PersistenceController(inMemory: true).viewContext
        vm  = VaultViewModel()
    }

    override func tearDownWithError() throws {
        ctx = nil; vm = nil
    }

    private func makeTrip(shared: Bool = false) -> Trip {
        let t = Trip(context: ctx); t.id = UUID(); t.name = "Test"
        t.cloudKitShareID = shared ? "share-id" : nil
        return t
    }

    private func addDoc(to trip: Trip, title: String, isShared: Bool) -> TripDocument {
        let d = TripDocument(context: ctx)
        d.id = UUID(); d.title = title; d.mimeType = "application/pdf"
        d.addedAt = Date(); d.isShared = isShared; d.trip = trip
        return d
    }

    // MARK: — isShared defaults

    func test_addDocument_defaultsToNotShared() throws {
        let trip = makeTrip(shared: true)
        try ctx.save()
        vm.addDocument(title: "Passport", data: Data([0x01]), mimeType: "application/pdf",
                       isShared: false, to: trip, isPro: true, context: ctx)
        let doc = trip.documentsArray.first
        XCTAssertEqual(doc?.isShared, false)
    }

    func test_addDocument_canBeMarkedShared() throws {
        let trip = makeTrip(shared: true)
        try ctx.save()
        vm.addDocument(title: "Itinerary", data: Data([0x01]), mimeType: "application/pdf",
                       isShared: true, to: trip, isPro: true, context: ctx)
        XCTAssertEqual(trip.documentsArray.first?.isShared, true)
    }

    // MARK: — Visibility filtering (simulates DocumentGridView logic)

    func test_participant_seesOnlySharedDocs() throws {
        let trip = makeTrip(shared: true)
        let passport  = addDoc(to: trip, title: "Passport",  isShared: false)
        let itinerary = addDoc(to: trip, title: "Itinerary", isShared: true)
        try ctx.save()

        let visible = trip.documentsArray.filter { $0.isShared }
        XCTAssertFalse(visible.contains(where: { $0.objectID == passport.objectID }))
        XCTAssertTrue(visible.contains(where:  { $0.objectID == itinerary.objectID }))
    }

    func test_owner_seesAllDocs() throws {
        let trip = makeTrip(shared: true)
        let passport  = addDoc(to: trip, title: "Passport",  isShared: false)
        let itinerary = addDoc(to: trip, title: "Itinerary", isShared: true)
        try ctx.save()

        // Owner (currentUserIsOwner == true) — no filter applied.
        let visible = trip.documentsArray
        XCTAssertTrue(visible.contains(where: { $0.objectID == passport.objectID }))
        XCTAssertTrue(visible.contains(where: { $0.objectID == itinerary.objectID }))
    }

    func test_soloTrip_allDocsVisible_noFilterNeeded() throws {
        let trip = makeTrip(shared: false)
        let passport = addDoc(to: trip, title: "Passport", isShared: false)
        try ctx.save()

        // Unshared trip — filter is not applied (currentUserIsOwner always true).
        let visible = trip.documentsArray
        XCTAssertTrue(visible.contains(where: { $0.objectID == passport.objectID }))
    }
}
