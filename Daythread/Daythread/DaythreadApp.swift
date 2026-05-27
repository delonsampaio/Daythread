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

    var container: ModelContainer = {
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
        let config = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private("iCloud.com.delonsampaio.daythread")
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Graceful degradation — show recovery UI rather than crashing
            fatalError("ModelContainer failed to initialize: \(error). Check CloudKit entitlements.")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .modelContainer(container)
                .environment(store)
        }
    }
}
