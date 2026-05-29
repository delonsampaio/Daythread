//
//  ProPaywallView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import StoreKit

struct ProPaywallView: View {
    @Environment(TripStore.self) private var store
    @State private var vm = ProfileViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Hero
                    VStack(spacing: 8) {
                        Image(systemName: "airplane.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(ThemeTokens.accentPro)
                        Text("Daythread Pro")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(ThemeTokens.accentPro)
                        Text("One-time purchase. Lifetime access.")
                            .font(.subheadline)
                            .foregroundStyle(ThemeTokens.textSecondary)
                    }
                    .padding(.top, 24)

                    // Feature list
                    VStack(alignment: .leading, spacing: 16) {
                        proRow("✈️ Real-time co-editing", "Share trips with friends and family. Changes sync in seconds.")
                        proRow("⏱ Running Late Mode", "ETA overlays on every event so the group always knows where you are.")
                        proRow("💸 Expense Splitting", "Log, split, and settle trip costs. Smart calculations find the easiest way to settle up.")
                        proRow("📎 Receipt Attachments", "Attach photos of receipts and invoices directly to expenses.")
                        proRow("📄 Unlimited Documents", "Free tier: 5 documents. Pro: unlimited passports, visas, PDFs.")
                        proRow("🌤 Weather Overlays", "7-day forecast pinned to each day on your itinerary.")
                        proRow("🛫 Live Flight Tracking", "Gate changes and delays pushed directly to your timeline.")
                        proRow("🔗 Group Sync", "Invite co-editors, propose activities, vote on plans.")
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 16)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if !vm.isFetchingProduct && vm.product == nil {
                        // Product failed to load
                        VStack(spacing: 8) {
                            Text("Could not load pricing.")
                                .font(.footnote)
                                .foregroundStyle(ThemeTokens.textSecondary)
                            Button("Retry") {
                                Task { await vm.syncProStatus(store: store) }
                            }
                            .font(.footnote.bold())
                            .foregroundStyle(ThemeTokens.accent)
                        }
                        .padding(.horizontal, 24)
                    }

                    Button {
                        Task { await vm.purchase(store: store) }
                    } label: {
                        Group {
                            if vm.isFetchingProduct || vm.isPurchasing {
                                ProgressView().tint(.white)
                            } else {
                                Text("Unlock Lifetime Pro — \(vm.product?.displayPrice ?? "$9.99")")
                                    .font(.system(size: 17, weight: .bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: 16).fill(ThemeTokens.accentPro))
                    }
                    .padding(.horizontal, 24)
                    .disabled(vm.isPurchasing || vm.isFetchingProduct || vm.product == nil)

                    Button("Restore Purchases") {
                        Task { await vm.restorePurchases(store: store) }
                    }
                    .font(.footnote)
                    .foregroundStyle(ThemeTokens.textSecondary)

                    Button("Not Now") { dismiss() }
                        .font(.footnote)
                        .foregroundStyle(ThemeTokens.textSecondary)
                        .padding(.bottom, 8)
                }
                .padding(.top, 12)
                .background(.regularMaterial)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(ThemeTokens.textSecondary)
                    }
                }
            }
        }
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismiss() }
        }
        .task { await vm.syncProStatus(store: store) }
    }

    @ViewBuilder
    private func proRow(_ title: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(title.components(separatedBy: " ").first ?? "")
                .font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.components(separatedBy: " ").dropFirst().joined(separator: " "))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ThemeTokens.textPrimary)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
        }
    }
}
