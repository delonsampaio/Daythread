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
                // Yield for ~2 frames so SwiftUI can commit the splash to the
                // display server before the synchronous ModelContainer init runs.
                //
                // ModelContainer.init requires @MainActor internally — calling it
                // off-actor deadlocks (background thread waits for MainActor which
                // is already suspended waiting for the background thread). So we
                // stay on @MainActor, but ensure the splash paints first so the
                // user never sees a frozen white screen.
                try? await Task.sleep(for: .milliseconds(32))
                container = Self.makeContainer()
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
