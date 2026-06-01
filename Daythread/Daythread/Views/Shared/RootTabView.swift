//
//  RootTabView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI

enum DaythreadTab: Hashable {
    case timeline, trips, vault, profile
}

struct RootTabView: View {
    @Binding var selectedTab: DaythreadTab

    var body: some View {
        // Classic .tabItem + .tag API: the only way to get the iPhone-style bottom
        // tab bar with icons + labels on iPad too. iOS 26's Tab() API renders a
        // text-only top bar / sidebar on regular-width iPad (icons hidden unless the
        // sidebar is expanded), which is not the consistent icon bar we want here.
        // On iPad, RootView routes to RootSplitView instead — this view is
        // compact-width only.
        TabView(selection: $selectedTab) {
            TimelineView()
                .tabItem { Label("Timeline", systemImage: ThemeTokens.tabTimeline) }
                .tag(DaythreadTab.timeline)
            TripsListView()
                .tabItem { Label("Trips", systemImage: ThemeTokens.tabTrips) }
                .tag(DaythreadTab.trips)
            VaultView()
                .tabItem { Label("Vault", systemImage: ThemeTokens.tabVault) }
                .tag(DaythreadTab.vault)
            ProfileView()
                .tabItem { Label("Profile", systemImage: ThemeTokens.tabProfile) }
                .tag(DaythreadTab.profile)
        }
    }
}
