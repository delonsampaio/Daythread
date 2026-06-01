//
//  DaythreadApp.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData
import StoreKit
import CloudKit

@main
struct DaythreadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = TripStore()
    private let persistence = PersistenceController.shared
    @AppStorage("daythread.userDisplayName") private var userDisplayName: String = ""

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .environment(store)
            // Co-editing: ShareSceneDelegate accepts the tapped CKShare invite
            // and posts .daythreadDidAcceptShare with the share record name. We
            // stash it on TripStore so RootTabView can switch to the joined trip
            // once it syncs in. DEVICE-ONLY — requires a real iCloud account.
            .onReceive(NotificationCenter.default.publisher(for: .daythreadDidAcceptShare)) { note in
                guard let recordName = note.userInfo?["recordName"] as? String else { return }
                store.pendingJoinShareRecordName = recordName
                let trips = (try? persistence.viewContext.fetch(Trip.fetchRequest())) ?? []
                store.resolvePendingJoin(in: trips)
            }
            // On first install the display name is blank, making the user appear
            // as "Me" or "Traveler" to co-editors. Seed it from iCloud — CloudKit
            // lets you discover your OWN identity via discoverUserIdentity without
            // a permission dialog. Best-effort: if iCloud is unavailable the user
            // just fills it in manually from Settings.
            .task {
                guard userDisplayName.isEmpty else { return }
                let container = CKContainer(identifier: "iCloud.com.delonsampaio.daythread")
                guard let recordID = try? await container.userRecordID() else { return }
                guard let identity = try? await container.userIdentity(forUserRecordID: recordID),
                      let components = identity.nameComponents else { return }
                let formatter = PersonNameComponentsFormatter()
                formatter.style = .medium        // first + last, no honorifics
                let full = formatter.string(from: components)
                if !full.isEmpty {
                    userDisplayName = full
                }
            }
            // Long-lived StoreKit 2 transaction listener — runs for the entire
            // app lifetime. Catches purchases completed on other devices,
            // Ask-to-Buy approvals, and any transaction not finalized in the
            // normal purchase flow. Must call transaction.finish() to remove
            // it from the queue regardless of the outcome.
            .task {
                for await result in Transaction.updates {
                    guard case .verified(let transaction) = result else { continue }
                    guard transaction.productID == StoreKitService.proProductID else { continue }
                    if transaction.revocationDate == nil {
                        store.isPro = true
                    } else {
                        // Purchase was refunded — revoke Pro.
                        store.isPro = false
                    }
                    await transaction.finish()
                }
            }
        }
    }
}
