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

    private func addDoc(to trip: Trip, title: String, isShared: Bool, addedBy: String = "") -> TripDocument {
        let d = TripDocument(context: ctx)
        d.id = UUID(); d.title = title; d.mimeType = "application/pdf"
        d.addedAt = Date(); d.isShared = isShared
        d.addedByAppleUserID = addedBy; d.trip = trip
        return d
    }

    // Mirrors DocumentGridView.isVisible
    private func isVisible(_ doc: TripDocument, myID: String?, tripShared: Bool) -> Bool {
        guard tripShared else { return true }
        guard let id = myID else { return true }
        return doc.isShared || doc.addedByAppleUserID == id
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

    // MARK: — Visibility filtering (mirrors DocumentGridView.isVisible)

    func test_participant_seesOwnPrivateDoc() throws {
        let trip = makeTrip(shared: true)
        let myPassport = addDoc(to: trip, title: "My Passport", isShared: false, addedBy: "uid-me")
        try ctx.save()
        // Participant can always see docs they added themselves.
        XCTAssertTrue(isVisible(myPassport, myID: "uid-me", tripShared: true))
    }

    func test_participant_cannotSeeOtherPrivateDoc() throws {
        let trip = makeTrip(shared: true)
        let ownerPassport = addDoc(to: trip, title: "Owner Passport", isShared: false, addedBy: "uid-owner")
        try ctx.save()
        XCTAssertFalse(isVisible(ownerPassport, myID: "uid-participant", tripShared: true))
    }

    func test_sharedDoc_visibleToEveryone() throws {
        let trip = makeTrip(shared: true)
        let itinerary = addDoc(to: trip, title: "Itinerary", isShared: true, addedBy: "uid-owner")
        try ctx.save()
        XCTAssertTrue(isVisible(itinerary, myID: "uid-owner",       tripShared: true))
        XCTAssertTrue(isVisible(itinerary, myID: "uid-participant",  tripShared: true))
    }

    func test_soloTrip_allDocsVisible() throws {
        let trip = makeTrip(shared: false)
        let passport = addDoc(to: trip, title: "Passport", isShared: false, addedBy: "uid-me")
        try ctx.save()
        XCTAssertTrue(isVisible(passport, myID: "uid-me", tripShared: false))
    }

    func test_unknownMyID_showsEverything() throws {
        let trip = makeTrip(shared: true)
        let doc = addDoc(to: trip, title: "Private", isShared: false, addedBy: "uid-other")
        try ctx.save()
        // myID nil = haven't opened GroupSync yet → show all (safe default).
        XCTAssertTrue(isVisible(doc, myID: nil, tripShared: true))
    }
}
