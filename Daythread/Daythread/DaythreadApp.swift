//
//  DaythreadApp.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData
import StoreKit

@main
struct DaythreadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = TripStore()
    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
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
