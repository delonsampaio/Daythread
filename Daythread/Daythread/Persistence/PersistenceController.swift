import CoreData
import CloudKit

extension Notification.Name {
    /// Posted on the main thread after remote changes are merged into the viewContext.
    /// Views bump a token on receipt to force @FetchRequest to re-evaluate, since
    /// mergeChanges alone does not always re-drive SwiftUI's fetched results.
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
        private static let key = "daythread.historyToken.v5"

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

        // automaticallyMergesChangesFromParent = false: CloudKit's auto-merge runs on
        // a background thread, firing objectWillChange on @ObservedObject managed objects
        // off-main ("Publishing from background threads") — which SwiftUI drops, so the
        // timeline never updates live. Instead we merge manually on the MAIN thread, only
        // at IMPORT-finished (the moment imported data is committed), via persistent history.
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

        // Local background saves (CalendarService, etc.) merge into the viewContext on main.
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

        // The live-refresh trigger. eventChangedNotification fires on IMPORT-finished —
        // the only moment imported CloudKit data is guaranteed committed to the store and
        // present in persistent history. queue:.main runs the merge synchronously on the
        // main thread (no background-thread publishing), and merging via objectIDNotification
        // fires NSInsertedObjectsKey so @FetchRequest adds the new co-editor rows live.
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            // DIAGNOSTIC: log every event so we can see whether a live change on the
            // other device triggers an IMPORT here while this app stays foregrounded.
            let state = event.endDate == nil ? "started" : "finished"
            if let error = event.error {
                print("☁️ Daythread CloudKit \(Self.kindString(event.type)) \(state) ERROR: \(error)")
            } else {
                print("☁️ Daythread CloudKit \(Self.kindString(event.type)) \(state)")
            }
            guard event.type == .import, event.endDate != nil else { return }
            MainActor.assumeIsolated {
                Self.mergeHistory(into: viewContext, anchor: historyAnchor)
            }
        }
    }

    // MARK: — History merge

    @MainActor
    private static func mergeHistory(into context: NSManagedObjectContext, anchor: HistoryAnchor) {
        let request: NSPersistentHistoryChangeRequest
        if let token = anchor.token {
            request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        } else {
            request = NSPersistentHistoryChangeRequest.fetchHistory(after: Date(timeIntervalSinceNow: -7 * 86400))
        }
        do {
            guard let result = try context.execute(request) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction],
                  !transactions.isEmpty else { return }
            for transaction in transactions {
                context.mergeChanges(fromContextDidSave: transaction.objectIDNotification())
            }
            // Re-fault so TripDay.events relationship caches flush and reflect the
            // newly merged child events when @FetchRequest re-evaluates.
            context.refreshAllObjects()
            anchor.save(transactions.last!.token)
            print("☁️ Daythread: merged \(transactions.count) history transaction(s) live")
            // Force SwiftUI views to re-evaluate: mergeChanges inserts the objects but
            // @FetchRequest does not always re-run from the merge notification alone.
            NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
        } catch {
            print("⚠️ Daythread: history merge failed — resetting token. \(error)")
            anchor.reset()
            context.refreshAllObjects()
        }
    }

    nonisolated private static func kindString(_ type: NSPersistentCloudKitContainer.EventType) -> String {
        switch type {
        case .setup:  return "SETUP"
        case .import: return "IMPORT"
        case .export: return "EXPORT"
        @unknown default: return "UNKNOWN"
        }
    }

    // MARK: — Manual refresh

    @MainActor
    func manualRefresh() async {
        Self.mergeHistory(into: viewContext, anchor: historyAnchor)
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
