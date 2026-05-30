//
//  ShareAcceptance.swift
//  Daythread
//
//  CloudKit share-acceptance plumbing for a SwiftUI lifecycle app.
//
//  When a recipient taps a CKShare invite link, the system launches the app and
//  calls userDidAcceptCloudKitShareWith on the scene delegate (NOT onOpenURL).
//  We accept the share via CKAcceptSharesOperation, then post a notification so
//  DaythreadApp can route to the joined trip using the (unit-tested)
//  TripStore.resolvePendingJoin path.
//
//  ⚠️ DEVICE-ONLY: requires a real iCloud account; cannot run on the simulator.
//

import UIKit
import CloudKit

extension Notification.Name {
    /// Posted after a CKShare is accepted. userInfo["recordName"] = share record name.
    static let daythreadDidAcceptShare = Notification.Name("DaythreadDidAcceptShare")
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
        let container = CKContainer(identifier: containerID)
        let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
        operation.acceptSharesResultBlock = { result in
            switch result {
            case .success:
                let recordName = metadata.share.recordID.recordName
                NotificationCenter.default.post(
                    name: .daythreadDidAcceptShare,
                    object: nil,
                    userInfo: ["recordName": recordName]
                )
            case .failure(let error):
                print("⚠️ Failed to accept CloudKit share: \(error)")
            }
        }
        container.add(operation)
    }
}
