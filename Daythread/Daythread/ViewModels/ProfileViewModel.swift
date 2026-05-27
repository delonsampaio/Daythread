//
//  ProfileViewModel.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import Foundation
import Observation

@Observable
final class ProfileViewModel {
    private let storeKit = StoreKitService()

    var isLoadingProduct: Bool = false
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
        await storeKit.fetchProducts()
        await storeKit.restorePurchases(store: store)
    }
}
