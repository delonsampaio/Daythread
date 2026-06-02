import CoreData
import CloudKit

extension Notification.Name {
    /// Posted on the main thread after remote changes are merged into the viewContext.
    /// Views observe this to force a re-render when objectWillChange alone does not
    /// fire (e.g. a TripDay whose events relationship changed via co-editor sync).
    nonisolated static let dayThreadRemoteChangeDidApply = Notification.Name("dayThreadRemoteChangeDidApply")
}

struct PersistenceController {
    static let shared = PersistenceController()

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

    // MARK: — Init

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

        // automaticallyMergesChangesFromParent = false: auto-merge triggers the merge
        // on whatever thread posts NSManagedObjectContextDidSave (often CloudKit's
        // background import thread), generating "Publishing from background threads"
        // warnings and potentially dropping SwiftUI updates. We merge manually on
        // the main queue in setupObservers() to guarantee thread safety.
        container.viewContext.automaticallyMergesChangesFromParent = false
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        container.viewContext.transactionAuthor = "DaythreadApp"

        if !inMemory {
            setupObservers()
        }
    }

    // MARK: — Observers

    private func setupObservers() {
        let viewContext = container.viewContext

        // Merge ALL context saves — local background saves AND CloudKit's internal
        // import contexts — on the main queue. queue:.main ensures the merge and
        // any resulting @FetchRequest/objectWillChange emissions happen on the main
        // thread, eliminating "Publishing from background threads" warnings.
        // No coordinator check: CloudKit's contexts may or may not share our
        // coordinator reference depending on iOS internals; skipping the check
        // ensures we never silently miss an import. Object IDs from unrelated stores
        // are silently ignored by mergeChanges, so this is always safe.
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { notification in
            guard let savedCtx = notification.object as? NSManagedObjectContext,
                  savedCtx !== viewContext
            else { return }
            viewContext.mergeChanges(fromContextDidSave: notification)
            NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
        }

        // NSPersistentStoreRemoteChange: belt-and-suspenders refresh after each
        // CloudKit import batch commits, in case any object wasn't caught by the
        // context-save observer above.
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { _ in
            Task { @MainActor in
                viewContext.refreshAllObjects()
                NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
            }
        }
    }

    // MARK: — Manual refresh

    @MainActor
    func manualRefresh() async {
        viewContext.refreshAllObjects()
        NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
        try? await Task.sleep(for: .milliseconds(500))
    }

    // MARK: — Debug

    #if DEBUG
    func initializeCloudKitSchemaIfNeeded() {
        do { try container.initializeCloudKitSchema(options: []) }
        catch { print("⚠️ initializeCloudKitSchema failed: \(error)") }
    }
    #endif

    // MARK: — Shared store

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
