//
//  VaultView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData
import Combine

struct VaultView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.managedObjectContext) private var context
    @State private var trips: [Trip] = []
    @State private var vm = VaultViewModel()
    @State private var selectedSegment: Int = 0

    /// Non-archived trips only, for the picker.
    private var activeTrips: [Trip] {
        trips.filter { !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeTrips.isEmpty {
                    ContentUnavailableView("No trips yet",
                                           systemImage: "airplane",
                                           description: Text("Create a trip in the Trips tab to get started."))
                } else if let trip = store.activeTrip {
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
                    // Trips exist but none selected — prompt user to pick one.
                    ContentUnavailableView("No trip selected",
                                           systemImage: "folder.fill",
                                           description: Text("Tap the trip name above to choose a trip."))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Tappable trip-picker title (iOS Mail-style).
                // Switching here updates store.activeTrip, keeping the Timeline in sync.
                ToolbarItem(placement: .principal) {
                    tripPickerTitle
                }
            }
            .sheet(isPresented: $vm.showPaywall) {
                ProPaywallView()
            }
            .task {
                reloadTrips()
                if store.activeTrip == nil, let first = activeTrips.first {
                    store.activeTrip = first
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dayThreadRemoteChangeDidApply)) { _ in reloadTrips() }
            .onReceive(
                NotificationCenter.default
                    .publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)
                    .throttle(for: .milliseconds(250), scheduler: DispatchQueue.main, latest: true)
            ) { _ in reloadTrips() }
        }
    }

    @ViewBuilder
    private var tripPickerTitle: some View {
        if activeTrips.isEmpty {
            Text("Vault")
                .font(.headline)
        } else {
            Menu {
                ForEach(activeTrips) { trip in
                    Button {
                        store.activeTrip = trip
                    } label: {
                        if trip.id == store.activeTrip?.id {
                            Label(trip.name, systemImage: "checkmark")
                        } else {
                            Text(trip.name)
                        }
                    }
                }
            } label: {
                VStack(spacing: 1) {
                    // The chevron is an overlay (via alignmentGuide) so it doesn't
                    // widen the name's layout frame — that keeps the date below
                    // centered under the trip name text, not under name + chevron.
                    Text(store.activeTrip?.isAlive == true ? store.activeTrip!.name : "Select Trip")
                        .font(.headline)
                        .foregroundStyle(ThemeTokens.textPrimary)
                        .overlay(alignment: .trailing) {
                            Image(systemName: "chevron.down")
                                .font(.caption2.bold())
                                .foregroundStyle(ThemeTokens.textSecondary)
                                .alignmentGuide(.trailing) { d in d[.leading] - 4 }
                        }
                    if let trip = store.activeTrip, trip.isAlive {
                        Text(dateRange(for: trip))
                            .font(.caption2)
                            .foregroundStyle(ThemeTokens.textMuted)
                    }
                }
            }
        }
    }

    private func reloadTrips() {
        let request = Trip.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Trip.startDate, ascending: false)]
        trips = (try? context.fetch(request)) ?? []
    }

    private func dateRange(for trip: Trip) -> String {
        let start = trip.startDate.formatted(.dateTime.month(.abbreviated).day())
        let end   = trip.endDate.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }
}
