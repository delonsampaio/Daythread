//
//  Stubs.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//
//  Temporary stubs — replaced in Tasks 16, 18, 19.
//  Delete this file when all real implementations land.
//

import SwiftUI

struct TripsListView: View {
    var body: some View { Text("Trips").font(.largeTitle) }
}

struct VaultView: View {
    var body: some View { Text("Vault").font(.largeTitle) }
}

struct ProfileView: View {
    var body: some View { Text("Profile").font(.largeTitle) }
}

// Temporary stub — replaced in Task 16
struct AddEditEventSheet: View {
    let trip: Trip?
    let day: TripDay?
    let vm: TimelineViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Event — coming soon")
                .font(.title2)
            Button("Dismiss") { dismiss() }
        }
    }
}
