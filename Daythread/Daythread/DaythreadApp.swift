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
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .task { NotificationService.shared.registerCategories() }
                // NSPersistentCloudKitContainer often fails to create the silent-push
                // subscription on the SHARED database, so participants only sync at
                // launch. Create it explicitly (idempotent) and log the current state.
                .task {
                    let ck = CloudKitService()
                    ck.ensureSharedDatabaseSubscription()
                    ck.ensurePrivateDatabaseSubscription()
                    ck.verifySharedDatabaseSubscription()
                    // Path A: start the local-edit push observer, then pull shared-zone
                    // changes at launch (or log-only when the flag is off).
                    SharedSyncEngine.shared.start()
                    await SharedSyncEngine.shared.fetchAllSharedZones()
                }
                // Pull on foreground, and poll while active (push alone is throttled
                // by iOS and eventually stops delivering). Stop polling in the background.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await SharedSyncEngine.shared.fetchAllSharedZones() }
                        SharedSyncEngine.shared.startPeriodicSync()
                    } else {
                        SharedSyncEngine.shared.stopPeriodicSync()
                    }
                }
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
            // Display name is set manually in Profile → Settings.
            // Auto-population via CKUserIdentity was removed — the API was
            // deprecated in iOS 17 and no longer returns data on iOS 26.
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
