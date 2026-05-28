//
//  VaultView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI

struct VaultView: View {
    @Environment(TripStore.self) private var store
    @State private var vm = VaultViewModel()
    @State private var selectedSegment: Int = 0

    var body: some View {
        NavigationStack {
            Group {
                if let trip = store.activeTrip {
                    VStack(spacing: 0) {
                        Picker("", selection: $selectedSegment) {
                            Text("Documents").tag(0)
                            Text("Expenses").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.vertical, 8)

                        if selectedSegment == 0 {
                            DocumentGridView(trip: trip, vm: vm)
                        } else {
                            ExpenseListView(trip: trip, vm: vm)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    ContentUnavailableView("No active trip",
                                           systemImage: "folder.fill",
                                           description: Text("Select a trip in the Trips tab."))
                }
            }
            .navigationTitle("Vault")
            .sheet(isPresented: $vm.showPaywall) {
                ProPaywallView()
            }
        }
    }
}
