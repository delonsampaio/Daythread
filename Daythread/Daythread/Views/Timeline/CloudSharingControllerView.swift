//
//  CloudSharingControllerView.swift
//  Daythread
//
//  UIViewControllerRepresentable wrapper around UICloudSharingController —
//  Apple's system sheet for sending a CKShare invite via Messages, Mail,
//  AirDrop, etc., and for managing participants on an existing share.
//
//  ⚠️ DEVICE-ONLY behaviour: the share it presents is created by
//  CloudKitTripSharingBackend, which only works on a physical device signed
//  into iCloud. The wrapper itself is inert UI glue and compiles everywhere.
//

import SwiftUI
import CloudKit
import UIKit

struct CloudSharingControllerView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    /// Title shown in the system share sheet (the trip name).
    let title: String
    /// Called when the user stops sharing from inside the system sheet, so the
    /// app can clear the trip's cloudKitShareID and stay in sync.
    var onStopSharing: () -> Void = {}

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowReadOnly, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(title: title, onStopSharing: onStopSharing) }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let title: String
        let onStopSharing: () -> Void

        init(title: String, onStopSharing: @escaping () -> Void) {
            self.title = title
            self.onStopSharing = onStopSharing
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            // Surfaced via the controller's own error UI; logged for diagnostics.
            print("⚠️ UICloudSharingController failed to save share: \(error)")
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onStopSharing()
        }
    }
}
