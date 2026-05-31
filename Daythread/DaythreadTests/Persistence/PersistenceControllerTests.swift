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
        let policy = controller.viewContext.mergePolicy as? NSMergePolicy
        XCTAssertEqual(policy?.mergeType, .mergeByPropertyObjectTrumpMergePolicyType)
    }

    func test_inMemoryController_setsTransactionAuthor() {
        let controller = PersistenceController(inMemory: true)
        XCTAssertEqual(controller.viewContext.transactionAuthor, "DaythreadApp")
    }

    /// Every container must share ONE NSManagedObjectModel instance. Re-loading
    /// the model per controller registers the same NSManagedObject subclass
    /// against multiple NSEntityDescriptions, making `+[Trip entity]` ambiguous
    /// ("Failed to find a unique match…") and intermittently breaking parallel
    /// tests. Sharing the model keeps entity resolution deterministic.
    func test_allControllers_shareOneManagedObjectModel() {
        let a = PersistenceController(inMemory: true)
        let b = PersistenceController(inMemory: true)
        XCTAssertTrue(
            a.container.managedObjectModel === b.container.managedObjectModel,
            "Controllers must share a single NSManagedObjectModel instance"
        )
    }
}
