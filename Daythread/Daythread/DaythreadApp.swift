//
//  DaythreadApp.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import SwiftData

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
        }
    }

    private static func makeContainer() -> ModelContainer {
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
        // Real device — try CloudKit (fast with a valid iCloud account).
        // Falls back to in-memory only if the device has no iCloud access at all.
        do {
            let config = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private("iCloud.com.delonsampaio.daythread")
            )
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [memConfig])
        }
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
