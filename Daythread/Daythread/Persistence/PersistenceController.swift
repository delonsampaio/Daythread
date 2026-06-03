import CoreData
import CloudKit
import os

/// Visible in Console.app on a real/TestFlight device (filter subsystem "Daythread").
/// print() only shows in the Xcode debugger, so we use Logger for on-device diagnostics.
nonisolated let daythreadLog = Logger(subsystem: "com.DelonSampaio.Daythread", category: "CloudKit")

extension Notification.Name {
    /// Posted on the main thread after a CloudKit import finishes. Views bump a
    /// token on receipt to force @FetchRequest / relationship arrays to re-evaluate.
    nonisolated static let dayThreadRemoteChangeDidApply = Notification.Name("dayThreadRemoteChangeDidApply")
}

struct PersistenceController {
    static let shared = PersistenceController()

    /// Path A rollout flag. While true, shared.sqlite is detached from
    /// NSPersistentCloudKitContainer and synced by the custom SharedSyncEngine
    /// (reliable participant sync). While false, the shared store stays on NSPCKC
    /// (the legacy path whose participant import is deferred indefinitely).
    /// Pull + push paths are built (Phases 0–4). Flipping ON for end-to-end validation.
    /// ⚠️ Validate with a CLEAN INSTALL (delete + reinstall) on both devices first —
    /// an in-place update over NSPCKC-imported shared data will duplicate records until
    /// the one-time shared-store cutover migration is added (post-validation).
    nonisolated static let useCustomSharedSync = true

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

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        container.viewContext.transactionAuthor = "DaythreadApp"

        if !inMemory {
            performSharedStoreCutoverIfNeeded()
            setupObservers()
        }
    }

    // MARK: — Path A cutover

    /// One-time migration when the custom shared-sync engine is first enabled.
    /// Existing participants have shared-trip objects that NSPCKC imported — those
    /// lack the ckRecordName/ckSystemFields the engine needs to match records, so a
    /// naive first sync would DUPLICATE everything. Wipe the local shared store once
    /// (it's only a mirror of the owner's CloudKit data); the engine then re-fetches
    /// it cleanly with proper identities. Only touches shared-with-me data; the
    /// private store (the user's own trips) is untouched.
    private func performSharedStoreCutoverIfNeeded() {
        let key = "daythread.sharedStoreCutover.v1"
        guard Self.useCustomSharedSync, !UserDefaults.standard.bool(forKey: key) else { return }
        guard let sharedStore = container.persistentStoreCoordinator.persistentStores
            .first(where: { $0.url?.lastPathComponent == "shared.sqlite" }) else { return }

        let context = container.viewContext
        for entity in CKRecordMapper.syncedEntities + ["SyncState"] {
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            let delete = NSBatchDeleteRequest(fetchRequest: fetch)
            delete.affectedStores = [sharedStore]
            _ = try? container.persistentStoreCoordinator.execute(delete, with: context)
        }
        context.reset()
        UserDefaults.standard.set(true, forKey: key)
        daythreadLog.log("Path A cutover: wiped local shared store for clean custom-sync re-fetch")
    }

    // MARK: — Observers

    private func setupObservers() {
        let viewContext = container.viewContext
        let container = container

        // CloudKit import finished: the data is committed and (via auto-merge) present
        // in the viewContext. Re-fault on the main thread and post the change signal so
        // views re-evaluate their fetched results / relationship arrays and show it live.
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            // DIAGNOSTIC: log EVERY event (started + finished) so we can see what fires
            // on A when it adds an event, and confirm whether B receives anything live.
            let state = event.endDate == nil ? "started" : "finished"
            if let error = event.error {
                daythreadLog.error("CloudKit \(Self.kindString(event.type), privacy: .public) \(state, privacy: .public) ERROR: \(error.localizedDescription, privacy: .public)")
            } else {
                daythreadLog.log("CloudKit \(Self.kindString(event.type), privacy: .public) \(state, privacy: .public)")
            }
            guard event.type == .import, event.endDate != nil else { return }
            MainActor.assumeIsolated {
                viewContext.refreshAllObjects()
                NotificationCenter.default.post(name: .dayThreadRemoteChangeDidApply, object: nil)
                daythreadLog.log("import applied — UI refresh posted")
            }
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

    // MARK: — Sync ping (wake the mirroring delegate)

    @MainActor private static var lastPingAt = Date.distantPast

    /// Writes a tiny change to the PRIVATE store to force NSPersistentCloudKitContainer's
    /// mirroring delegate to wake up. The participant's stalled SHARED-database import is
    /// flushed as a side effect of the resulting private export cycle. Called when a CloudKit
    /// silent push arrives. Debounced to avoid ping-pong between a single user's own devices
    /// (the ping lives in the private DB, so it never reaches the other CKShare participant).
    @MainActor
    func pokeSyncPing() {
        let now = Date()
        guard now.timeIntervalSince(Self.lastPingAt) > 3 else { return }
        Self.lastPingAt = now

        let ctx = viewContext
        let request = SyncPing.fetchRequest()
        request.fetchLimit = 1
        let ping: SyncPing
        if let existing = (try? ctx.fetch(request))?.first {
            ping = existing
        } else {
            ping = SyncPing(context: ctx)
            ping.id = UUID()
            // Keep it out of the shared store so it only wakes the private export cycle.
            if let privateStore = ctx.persistentStoreCoordinator?.persistentStores
                .first(where: { $0.url?.lastPathComponent != "shared.sqlite" }) {
                ctx.assign(ping, to: privateStore)
            }
        }
        ping.updatedAt = now
        do {
            try ctx.save()
            daythreadLog.log("SyncPing poked — waking mirroring delegate to flush shared import")
        } catch {
            daythreadLog.error("SyncPing save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: — Manual refresh

    @MainActor
    func manualRefresh() async {
        pokeSyncPing()
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
        // History tracking stays on regardless: the custom engine uses persistent
        // history on shared.sqlite to detect local participant edits to push.
        sharedDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        sharedDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        if Self.useCustomSharedSync {
            // Path A: detach from NSPCKC — shared.sqlite becomes a plain local store
            // that SharedSyncEngine mirrors to/from the CKShare zones manually.
            sharedDescription.cloudKitContainerOptions = nil
        } else {
            // Legacy path: NSPCKC mirrors the shared store (participant import deferred).
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.delonsampaio.daythread")
            options.databaseScope = .shared
            sharedDescription.cloudKitContainerOptions = options
        }
        container.persistentStoreDescriptions.append(sharedDescription)
    }
}
