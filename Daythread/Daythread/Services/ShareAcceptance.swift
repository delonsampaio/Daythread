//
//  ShareAcceptance.swift
//  Daythread
//
//  CloudKit share-acceptance plumbing for a SwiftUI lifecycle app.
//
//  When a recipient taps a CKShare invite link, the system launches the app and
//  calls userDidAcceptCloudKitShareWith on the scene delegate (NOT onOpenURL).
//  We accept the share through NSPersistentCloudKitContainer.acceptShareInvitations
//  so Core Data imports the shared object graph into the SHARED store — accepting
//  via a bare CKAcceptSharesOperation would join the CloudKit share but never
//  surface the records to Core Data. After acceptance we post a notification so
//  DaythreadApp can route to the joined trip via TripStore.resolvePendingJoin.
//
//  ⚠️ DEVICE-ONLY: requires a real iCloud account; cannot run on the simulator.
//

import UIKit
import CloudKit
import CoreData
import os

extension Notification.Name {
    /// Posted after a CKShare is accepted. userInfo["recordName"] = share record name.
    ///
    /// `nonisolated` because it is referenced from `acceptShareInvitations`'s
    /// completion handler — a non-isolated Sendable closure. The value is an
    /// immutable `Sendable` `Notification.Name`, so cross-context reads are safe.
    nonisolated static let daythreadDidAcceptShare = Notification.Name("DaythreadDidAcceptShare")
}

/// App delegate that installs a scene delegate capable of handling CloudKit
/// share acceptance. Wired into DaythreadApp via @UIApplicationDelegateAdaptor.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Required for CloudKit real-time sync. NSPersistentCloudKitContainer relies
        // on silent APNs pushes to know when co-editors make changes. Without this
        // call, the OS never delivers those pushes and NSPersistentStoreRemoteChange
        // never fires — changes only appear when the app is closed and reopened
        // (which triggers a mandatory catch-up fetch on next launch).
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("✅ Daythread: registered for APNs — CloudKit real-time sync enabled")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Daythread: APNs registration failed — CloudKit sync will be delayed: \(error.localizedDescription)")
    }

    /// REQUIRED for live CloudKit sync in a SwiftUI @UIApplicationDelegateAdaptor app.
    /// iOS 13+ inspects the AppDelegate and, if this method is absent, assumes the app
    /// can't handle silent (content-available) pushes — and drops them before Core
    /// Data's swizzled handler ever sees them, so the participant only syncs at cold
    /// launch. Implementing even this stub makes the OS deliver the push; Core Data's
    /// swizzle wraps around it and runs the shared-DB import.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        daythreadLog.log("remote notification received (silent CloudKit push)")
        Task { @MainActor in
            if PersistenceController.useCustomSharedSync {
                // Path A: pull shared-zone changes immediately (no dasd deferral).
                await SharedSyncEngine.shared.fetchAllSharedZones()
            } else {
                // Legacy path: poke the private store to wake NSPCKC's mirroring delegate.
                PersistenceController.shared.pokeSyncPing()
            }
        }
        completionHandler(.newData)
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = ShareSceneDelegate.self
        return config
    }
}

/// Scene delegate whose sole job is to receive accepted CloudKit shares.
/// SwiftUI continues to own the window and view hierarchy.
final class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    private let containerID = "iCloud.com.delonsampaio.daythread"

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        if PersistenceController.useCustomSharedSync {
            acceptViaCustomEngine(metadata)
        } else {
            acceptViaNSPCKC(metadata)
        }
    }

    /// Path A: the shared store is severed from NSPCKC, so `acceptShareInvitations`
    /// won't work. Accept the share with a raw CKAcceptSharesOperation, then trigger
    /// the custom engine to pull the newly-joined zone into shared.sqlite.
    private func acceptViaCustomEngine(_ metadata: CKShare.Metadata) {
        let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
        operation.qualityOfService = .userInitiated
        operation.acceptSharesResultBlock = { result in
            switch result {
            case .success:
                daythreadLog.log("CKShare accepted (custom engine) — fetching joined zone")
                let zoneID = metadata.share.recordID.zoneID
                Task { @MainActor in
                    await SharedSyncEngine.shared.fetchJoinedZone(zoneID)
                }
                self.postAcceptance(metadata)
            case .failure(let error):
                daythreadLog.error("CKShare accept failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        CKContainer(identifier: containerID).add(operation)
    }

    /// Legacy path: let NSPCKC import the shared graph into the (still-mirrored) shared store.
    private func acceptViaNSPCKC(_ metadata: CKShare.Metadata) {
        let persistentContainer = PersistenceController.shared.cloudKitContainer
        guard let sharedStore = Self.sharedStore(in: persistentContainer) else {
            print("⚠️ No shared Core Data store found to accept the share into")
            return
        }
        persistentContainer.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            if let error {
                print("⚠️ Failed to accept CloudKit share: \(error)")
                return
            }
            self.postAcceptance(metadata)
        }
    }

    /// Post on main so DaythreadApp.onReceive sets pendingJoinShareRecordName before
    /// any onChange handlers run (avoids a race with main-thread join resolution).
    /// nonisolated: invoked from CloudKit's nonisolated completion blocks; it only
    /// hops to main to post a notification (no actor-isolated state).
    nonisolated private func postAcceptance(_ metadata: CKShare.Metadata) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .daythreadDidAcceptShare,
                object: nil,
                userInfo: ["recordName": metadata.share.recordID.recordName]
            )
        }
    }

    /// The persistent store scoped to CloudKit's shared database, identified by
    /// its "shared.sqlite" filename (set in PersistenceController.addSharedStore).
    private static func sharedStore(in container: NSPersistentCloudKitContainer) -> NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first {
            $0.url?.lastPathComponent == "shared.sqlite"
        }
    }
}
