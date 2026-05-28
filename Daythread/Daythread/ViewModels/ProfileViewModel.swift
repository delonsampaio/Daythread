//
//  ProfileViewModel.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import Foundation
import StoreKit
import Observation

@Observable
final class ProfileViewModel {
    private let storeKit = StoreKitService()

    /// The fetched Pro product — nil until fetchProducts completes.
    var product: Product? { storeKit.product }
    /// True while the purchase sheet is in-flight.
    var isPurchasing: Bool { storeKit.isPurchasing }
    /// True while fetchProducts() is running.
    var isFetchingProduct: Bool = false
    /// Non-nil if any StoreKit operation failed.
    var errorMessage: String? { storeKit.errorMessage }

    @MainActor
    func purchase(store: TripStore) async {
        await storeKit.purchase(store: store)
    }

    @MainActor
    func restorePurchases(store: TripStore) async {
        await storeKit.restorePurchases(store: store)
    }

    @MainActor
    func syncProStatus(store: TripStore) async {
        isFetchingProduct = true
        await storeKit.fetchProducts()
        isFetchingProduct = false
        await storeKit.restorePurchases(store: store)
    }
}
