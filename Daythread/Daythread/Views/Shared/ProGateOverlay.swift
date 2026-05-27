//
//  ProGateOverlay.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI

/// Wraps any view to show a lock badge when the user is not Pro.
/// Tapping the overlay on a non-Pro user presents ProPaywallView.
struct ProGateOverlay<Content: View>: View {
    @Environment(TripStore.self) private var store
    @State private var showPaywall = false
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .overlay {
                if !store.isPro {
                    ZStack(alignment: .topTrailing) {
                        Color.black.opacity(0.35)
                            .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.cardCornerRadius))
                            .contentShape(RoundedRectangle(cornerRadius: ThemeTokens.cardCornerRadius))
                            .onTapGesture { showPaywall = true }

                        Image(systemName: "lock.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Circle().fill(ThemeTokens.accentPro))
                            .padding(8)
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                ProPaywallView()
            }
    }
}
