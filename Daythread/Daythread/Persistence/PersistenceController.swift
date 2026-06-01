import CoreData
import CloudKit

struct PersistenceController {
    static let shared = PersistenceController()

    /// The Core Data model, loaded exactly once and shared by every container.
    ///
    /// `NSPersistentCloudKitContainer(name:)` reloads the model from the bundle
    /// each call. When several controllers exist at once (e.g. parallel tests),
    /// each fresh model registers the same NSManagedObject subclass against a
    /// different NSEntityDescription, so `+[Trip entity]` can't resolve uniquely
    /// ("Failed to find a unique match…") and `Trip(context:)` intermittently
    /// fails. Caching one model instance keeps entity resolution deterministic.
    private static let managedObjectModel: NSManagedObjectModel = {
        let bundle = Bundle(for: Trip.self)
        if let url = bundle.url(forResource: "Daythread", withExtension: "momd"),
           let model = NSManagedObjectModel(contentsOf: url) {
            return model
        }
        if let url = bundle.url(forResource: "Daythread", withExtension: "mom"),
           let model = NSManagedObjectModel(contentsOf: url) {
            return model
        }
        fatalError("Failed to load Core Data model 'Daythread'")
    }()

    let container: NSPersistentCloudKitContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    /// Exposed for the sharing backend and share-acceptance flow.
    var cloudKitContainer: NSPersistentCloudKitContainer { container }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(
            name: "Daythread",
            managedObjectModel: Self.managedObjectModel
        )

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Missing persistent store description")
        }

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
            description.cloudKitContainerOptions = nil
        } else {
            // Private database (owner's own trips + their other devices).
            description.cloudKitContainerOptions =
                NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.delonsampaio.daythread")
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        if !inMemory {
            addSharedStore()
        }

        container.loadPersistentStores { _, error in
            if let error { fatalError("Core Data store failed: \(error)") }
        }

        // Do NOT use automaticallyMergesChangesFromParent — it merges on whatever
        // background thread CloudKit's private import context fires from, which
        // triggers SwiftUI's "Publishing changes from background threads" warning
        // for every @Observable/@ObservedObject watching that data. Instead we
        // listen for context saves and explicitly dispatch the merge to the main
        // thread so @Observable property changes are always announced correctly.
        container.viewContext.automaticallyMergesChangesFromParent = false
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        container.viewContext.transactionAuthor = "DaythreadApp"

        if !inMemory {
            let viewContext = container.viewContext
            NotificationCenter.default.addObserver(
                forName: .NSManagedObjectContextDidSave,
                object: nil,
                queue: .main
            ) { notification in
                guard let savedCtx = notification.object as? NSManagedObjectContext,
                      savedCtx !== viewContext,
                      savedCtx.persistentStoreCoordinator === viewContext.persistentStoreCoordinator
                else { return }
                // Delivered on `.main` (queue: .main) and viewContext is the
                // main-queue context, so we're already on the correct queue —
                // merge directly. Wrapping in viewContext.perform would push the
                // non-Sendable `notification` into a @Sendable closure (Swift 6
                // capture error) for no benefit.
                viewContext.mergeChanges(fromContextDidSave: notification)
            }
        }
    }

    /// Run ONCE on a real device to push the record types to CloudKit's Development
    /// environment. Remove the call after the schema has been pushed.
    #if DEBUG
    func initializeCloudKitSchemaIfNeeded() {
        do { try container.initializeCloudKitSchema(options: []) }
        catch { print("⚠️ initializeCloudKitSchema failed: \(error)") }
    }
    #endif

    /// Adds a second store description scoped to CloudKit's shared database so
    /// records from accepted CKShares sync into a separate SQLite store.
    private func addSharedStore() {
        guard let privateDescription = container.persistentStoreDescriptions.first,
              let privateURL = privateDescription.url else { return }
        let sharedURL = privateURL.deletingLastPathComponent().appendingPathComponent("shared.sqlite")
        let sharedDescription = NSPersistentStoreDescription(url: sharedURL)
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.delonsampaio.daythread")
        options.databaseScope = .shared
        sharedDescription.cloudKitContainerOptions = options
        sharedDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        sharedDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        container.persistentStoreDescriptions.append(sharedDescription)
    }
}
