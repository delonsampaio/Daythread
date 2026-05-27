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
        // Try CloudKit first; fall back to local SQLite if unavailable (simulator / tests).
        // NOTE: isStoredInMemoryOnly is intentionally NOT used — @Attribute(.externalStorage)
        // requires a real file URL and throws when the store has no backing path.
        do {
            let config = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private("iCloud.com.delonsampaio.daythread")
            )
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Fallback: in-memory store — no CloudKit, no file I/O.
            // isStoredInMemoryOnly init has no cloudKitDatabase parameter, so CloudKit is
            // explicitly excluded.  All @externalStorage attrs are now Data? so the in-memory
            // store can handle them (stores nil inline; never tries to write a file).
            let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [memConfig])
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
