//
//  RootSplitView.swift
//  Daythread
//
//  Created by Delon Sampaio on 6/1/26.
//

import SwiftUI

struct RootSplitView: View {
    @Binding var selectedTab: DaythreadTab
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    // List(selection:) on iOS requires Optional<SelectionValue>
    @State private var listSelection: DaythreadTab? = .timeline

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $listSelection) {
                Label("Timeline", systemImage: ThemeTokens.tabTimeline).tag(DaythreadTab.timeline)
                Label("Trips",    systemImage: ThemeTokens.tabTrips).tag(DaythreadTab.trips)
                Label("Vault",    systemImage: ThemeTokens.tabVault).tag(DaythreadTab.vault)
                Label("Profile",  systemImage: ThemeTokens.tabProfile).tag(DaythreadTab.profile)
            }
            .listStyle(.sidebar)
            .navigationTitle("Daythread")
            // Keep listSelection and selectedTab in sync bidirectionally so that
            // a size-class flip (Stage Manager resize) preserves the active section.
            .onChange(of: listSelection) { _, new in
                if let new { selectedTab = new }
            }
            .onChange(of: selectedTab) { _, new in
                listSelection = new
            }
        } detail: {
            switch selectedTab {
            case .timeline: TimelineView()
            case .trips:    TripsListView()
            case .vault:    VaultView()
            case .profile:  ProfileView()
            }
        }
    }
}
