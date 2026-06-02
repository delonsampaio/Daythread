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

    // MARK: — Persistent history token

    @MainActor
    private final class HistoryAnchor {
        // v4 suffix forces a fresh start after the Phase 2 Core Data model change.
        private static let key = "daythread.historyToken.v4"

        var token: NSPersistentHistoryToken? = {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSPersistentHistoryToken.self, from: data
            )
        }()

        func save(_ newToken: NSPersistentHistoryToken) {
            token = newToken
            if let data = try? NSKeyedArchiver.archivedData(
                withRootObject: newToken, requiringSecureCoding: true
            ) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
        }

        func reset() {
            token = nil
            UserDefaults.standard.removeObject(forKey: Self.key)
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

        // automaticallyMergesChangesFromParent = false: we merge manually via
        // persistent history on the main actor so all state changes are serialised
        // on the main thread. This prevents "Publishing from background threads" warnings.
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
        let container = container
        let historyAnchor = historyAnchor

        // NSManagedObjectContextDidSave: merges our own local background context saves
        // (drag-reorder, CalendarService, etc.) into the viewContext on the main queue.
        // CloudKit imports bypass this notification — they fire NSPersistentStoreRemoteChange.
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { notification in
            guard let savedCtx = notification.object as? NSManagedObjectContext,
                  savedCtx !== viewContext,
                  savedCtx.persistentStoreCoordinator === viewContext.persistentStoreCoordinator
            else { return }
            viewContext.mergeChanges(fromContextDidSave: notification)
        }

        // NSPersistentStoreRemoteChange: the authoritative signal for CloudKit imports.
        // object: nil (not coordinator) follows Apple's own sample code — using the
        // coordinator reference as a filter has been observed to miss notifications
        // in multi-store setups where the notification object may differ from the
        // reference captured at setup time.
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { _ in
            print("🔄 Daythread: NSPersistentStoreRemoteChange received")
            Task { @MainActor in
                Self.mergeRemoteHistory(into: viewContext, anchor: historyAnchor)
            }
        }

        // eventChangedNotification fires after a CloudKit import fully commits to disk.
        // NSPersistentStoreRemoteChange can fire before all records are written, so this
        // provides a reliable second-pass merge for the tail of each import batch.
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: nil
        ) { notification in
            guard
                let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                event.type == .import,
                event.endDate != nil
            else { return }
            Task { @MainActor in
                Self.mergeRemoteHistory(into: viewContext, anchor: historyAnchor)
            }
        }
    }

    // MARK: — History merge

    @MainActor
    private static func mergeRemoteHistory(
        into context: NSManagedObjectContext,
        anchor: HistoryAnchor
    ) {
        // When token is nil (fresh start or after reset), fetch the last 7 days
        // of history so we catch any co-editor changes that arrived while the app
        // was offline, without replaying all-time history.
        let request: NSPersistentHistoryChangeRequest
        if let token = anchor.token {
            request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        } else {
            let since = Date(timeIntervalSinceNow: -7 * 86400)
            request = NSPersistentHistoryChangeRequest.fetchHistory(after: since)
        }

        do {
            guard let result = try context.execute(request) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction] else {
                print("🔄 Daythread: history result was nil or wrong type — refreshing objects only")
                context.refreshAllObjects()
                NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
                return
            }

            print("🔄 Daythread: found \(transactions.count) history transaction(s)")

            if transactions.isEmpty {
                context.refreshAllObjects()
                NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
                return
            }

            for transaction in transactions {
                context.mergeChanges(fromContextDidSave: transaction.objectIDNotification())
            }
            context.refreshAllObjects()
            anchor.save(transactions.last!.token)
            print("🔄 Daythread: merge complete, token updated")

        } catch {
            print("⚠️ Daythread: persistent history fetch failed — resetting token. \(error)")
            anchor.reset()
            context.refreshAllObjects()
        }

        NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
    }

    // MARK: — Manual refresh

    @MainActor
    func manualRefresh() async {
        Self.mergeRemoteHistory(into: viewContext, anchor: historyAnchor)
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
