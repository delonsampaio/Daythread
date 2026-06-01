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
        let persistentContainer = PersistenceController.shared.cloudKitContainer

        // Accept INTO the shared store so Core Data imports the shared object
        // graph (trip + days + events). The shared store is the one the
        // PersistenceController created with databaseScope == .shared.
        guard let sharedStore = Self.sharedStore(in: persistentContainer) else {
            print("⚠️ No shared Core Data store found to accept the share into")
            return
        }

        persistentContainer.acceptShareInvitations(
            from: [metadata],
            into: sharedStore
        ) { _, error in
            if let error {
                print("⚠️ Failed to accept CloudKit share: \(error)")
                return
            }
            // Post on main so DaythreadApp.onReceive sets pendingJoinShareRecordName
            // before any onChange handlers run (those execute on main). Without this,
            // the background-thread post can race with main-thread onChange calls that
            // check pendingJoinShareRecordName before it's been written.
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .daythreadDidAcceptShare,
                    object: nil,
                    userInfo: ["recordName": metadata.share.recordID.recordName]
                )
            }
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
