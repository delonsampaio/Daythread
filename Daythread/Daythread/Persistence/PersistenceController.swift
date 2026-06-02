import CoreData
import CloudKit

extension Notification.Name {
    /// Posted on the main thread after NSPersistentStoreRemoteChange applies
    /// refreshAllObjects() — views observe this to force a re-render when
    /// objectWillChange alone does not fire (e.g. faulted relationship caches).
    static let dayThreadRemoteChangeDidApply = Notification.Name("dayThreadRemoteChangeDidApply")
}

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

        // automaticallyMergesChangesFromParent = false — merging on whatever
        // background thread CloudKit's private import context fires from triggers
        // SwiftUI's "Publishing changes from background threads" warning for every
        // @ObservedObject watching that data. New managed objects (e.g. a freshly
        // accepted shared trip) reach the viewContext via the NSManagedObjectContextDidSave
        // observer below, which dispatches mergeChanges(fromContextDidSave:) to the
        // main thread. Existing objects are refreshed by the NSPersistentStoreRemoteChange
        // observer. Share-link resolution is handled by resolvePendingJoin in the
        // eventChangedNotification handler, which fires after the import completes.
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
                // Delivered on `.main` queue — safe to merge directly.
                // This fires for both local saves and CloudKit's internal import
                // context saves, inserting new managed objects (e.g. a newly
                // accepted shared trip) into the viewContext on the main thread
                // without triggering background-publishing warnings.
                viewContext.mergeChanges(fromContextDidSave: notification)
            }

            // CloudKit's remote import does NOT post NSManagedObjectContextDidSave
            // on the viewContext — it writes into a private background context and
            // posts NSPersistentStoreRemoteChange instead. Without this observer,
            // edits made by co-editors only appear after the app restarts.
            // NSPersistentStoreRemoteChangeNotificationPostOptionKey is already set
            // on both stores (lines 53 and 115) so this fires whenever CloudKit
            // finishes importing remote changes.
            let coordinator = container.persistentStoreCoordinator
            NotificationCenter.default.addObserver(
                forName: .NSPersistentStoreRemoteChange,
                object: coordinator,
                queue: nil          // delivered on a background thread; dispatch explicitly
            ) { _ in
                // mergeChanges(fromContextDidSave:) requires the save notification,
                // which we don't have here. Use refreshAllObjects so the viewContext
                // re-faults every stale managed object from the store, picking up
                // whatever CloudKit just imported. Must run on the viewContext's queue.
                viewContext.perform {
                    viewContext.refreshAllObjects()
                    // refreshAllObjects() re-faults objects but does not reliably
                    // fire objectWillChange on every @ObservedObject (notably a
                    // TripDay whose events relationship changed). Post an explicit
                    // signal so views can force a re-render. Already on the
                    // viewContext's main queue (viewContext is main-thread bound).
                    NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
                }
            }
        }
    }

    /// Manual pull-to-refresh action. NSPersistentCloudKitContainer syncs in the
    /// background automatically, but re-faulting the viewContext surfaces anything
    /// already imported into the store that hasn't yet re-rendered, and the posted
    /// notification forces views to re-read their relationships. The brief delay
    /// keeps the refresh spinner on screen long enough to read as deliberate.
    @MainActor
    func manualRefresh() async {
        viewContext.refreshAllObjects()
        NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
        try? await Task.sleep(for: .milliseconds(500))
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
