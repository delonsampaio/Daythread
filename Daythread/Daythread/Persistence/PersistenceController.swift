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

    // MARK: — Persistent history token

    /// Tracks the last persistent history transaction merged into the viewContext.
    /// @MainActor ensures token reads and writes are compile-time guaranteed to
    /// happen on the main thread — no nonisolated(unsafe) needed.
    @MainActor
    private final class HistoryAnchor {
        var token: NSPersistentHistoryToken? = {
            guard let data = UserDefaults.standard.data(forKey: "daythread.historyToken") else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSPersistentHistoryToken.self, from: data
            )
        }()

        func save(_ newToken: NSPersistentHistoryToken) {
            token = newToken
            if let data = try? NSKeyedArchiver.archivedData(
                withRootObject: newToken, requiringSecureCoding: true
            ) {
                UserDefaults.standard.set(data, forKey: "daythread.historyToken")
            }
        }
    }
    private let historyAnchor = HistoryAnchor()

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

        // automaticallyMergesChangesFromParent = false: CloudKit's import runs on
        // a background thread. With auto-merge on, SwiftUI fires "Publishing from
        // background threads" for every @ObservedObject on every sync event. We
        // merge manually via persistent history inside viewContext.perform (main
        // thread) so objectWillChange always fires on the correct thread.
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
        let coordinator = container.persistentStoreCoordinator
        let historyAnchor = historyAnchor

        // NSPersistentStoreRemoteChange fires after CloudKit finishes importing
        // remote records AND after the persistent history transactions are committed.
        // We use persistent history (not refreshAllObjects alone) because:
        // - refreshAllObjects re-faults existing objects but cannot INSERT new ones
        // - a co-editor's new event doesn't exist in the viewContext at all until
        //   mergeChanges(fromContextDidSave:) inserts it
        // - After the merge we still call refreshAllObjects to clear relationship
        //   caches (objectIDNotification inserts events as faults without updating
        //   the in-memory TripDay.events cache, so eventsArray would return stale
        //   data on the next read without a cache flush).
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: coordinator,
            queue: nil
        ) { _ in
            // Task { @MainActor in } hops to the main actor, giving compile-time
            // safety for both the @MainActor-isolated HistoryAnchor and the
            // NSManagedObjectContext (main-queue bound) operations inside merge.
            Task { @MainActor in
                Self.mergeRemoteHistory(into: viewContext, anchor: historyAnchor)
            }
        }
    }

    // MARK: — History merge (shared by observer + manualRefresh)

    /// Fetches all persistent history transactions since the last token, merges
    /// them into `context`, clears relationship caches, updates the anchor, and
    /// posts dayThreadRemoteChangeDidApply. Must be called on the context's queue.
    @MainActor
    private static func mergeRemoteHistory(
        into context: NSManagedObjectContext,
        anchor: HistoryAnchor
    ) {
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: anchor.token)
        guard let result = try? context.execute(request) as? NSPersistentHistoryResult,
              let transactions = result.result as? [NSPersistentHistoryTransaction],
              !transactions.isEmpty else {
            // No new history — clear caches and signal anyway so pull-to-refresh
            // and the re-render token always reflect the current store state.
            context.refreshAllObjects()
            NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
            return
        }

        // Merge each transaction: inserts new objects (co-editor adds), updates
        // existing ones, removes deleted ones.
        for transaction in transactions {
            context.mergeChanges(fromContextDidSave: transaction.objectIDNotification())
        }

        // objectIDNotification() inserts objects as faults without updating
        // in-memory relationship caches. Without this flush, TripDay.events
        // still returns the stale cached set on the next eventsArray read.
        context.refreshAllObjects()

        if let last = transactions.last {
            anchor.save(last.token)
        }
        NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
    }

    // MARK: — Manual refresh

    /// Pull-to-refresh: merges un-processed history, clears caches, signals views.
    /// The brief sleep keeps the spinner visible long enough to feel deliberate.
    @MainActor
    func manualRefresh() async {
        Self.mergeRemoteHistory(into: viewContext, anchor: historyAnchor)
        try? await Task.sleep(for: .milliseconds(500))
    }

    // MARK: — Debug

    /// Run ONCE on a real device to push the record types to CloudKit's Development
    /// environment. Remove the call after the schema has been pushed.
    #if DEBUG
    func initializeCloudKitSchemaIfNeeded() {
        do { try container.initializeCloudKitSchema(options: []) }
        catch { print("⚠️ initializeCloudKitSchema failed: \(error)") }
    }
    #endif

    // MARK: — Shared store

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
