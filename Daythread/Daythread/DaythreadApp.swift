//
//  DaythreadApp.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import SwiftData
import StoreKit

@main
struct DaythreadApp: App {
    @State private var store = TripStore()
    @State private var container: ModelContainer?

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootTabView()
                        .modelContainer(container)
                        .environment(store)
                } else {
                    LaunchSplashView()
                }
            }
            .task {
                guard container == nil else { return }
                // Run container init on a background thread so CloudKit's
                // blocking setup (can take 1-3s on first launch) doesn't
                // freeze the main thread. The splash stays visible until
                // the container is ready, then SwiftUI swaps in RootTabView.
                let built = await Task.detached(priority: .userInitiated) {
                    Self.makeContainer()
                }.value
                container = built
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

    private nonisolated static func makeContainer() -> ModelContainer {
        let schema = Schema([
            Trip.self,
            TripDay.self,
            TripEvent.self,
            TransitDetails.self,
            LodgingInfo.self,
            TripMember.self,
            TripDocument.self,
            TripExpense.self,
            PreTripTask.self
        ])

        #if targetEnvironment(simulator)
        // Simulator has no iCloud account. CloudKit's recovery process can block
        // for 30–60 s waiting for a network timeout, causing the app to hang.
        // Use in-memory on Simulator so tests and dev iteration are instant.
        let simConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [simConfig])
        #else
        // TEST: local store only — bypassing CloudKit to isolate launch hang
        let localConfig = ModelConfiguration(schema: schema)
        return try! ModelContainer(for: schema, configurations: [localConfig])
        #endif
    }
}

private struct LaunchSplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "airplane.departure")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                ProgressView()
            }
        }
    }
}
