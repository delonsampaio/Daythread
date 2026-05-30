import XCTest
import CoreData
@testable import Daythread

@MainActor
final class PersistenceControllerTests: XCTestCase {
    func test_inMemoryController_savesAndFetchesTrip() throws {
        let controller = PersistenceController(inMemory: true)
        let ctx = controller.viewContext

        let trip = Trip(context: ctx)
        trip.id = UUID()
        trip.name = "Paris"
        trip.startDate = .now
        trip.endDate = .now
        try ctx.save()

        let fetched = try ctx.fetch(Trip.fetchRequest())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Paris")
    }

    func test_inMemoryController_mergePolicyIsObjectTrump() {
        let controller = PersistenceController(inMemory: true)
        XCTAssertEqual(
            controller.viewContext.mergePolicy as? NSMergePolicy,
            NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        )
    }

    func test_inMemoryController_setsTransactionAuthor() {
        let controller = PersistenceController(inMemory: true)
        XCTAssertEqual(controller.viewContext.transactionAuthor, "DaythreadApp")
    }
}
