//
//  StoreKitService.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import StoreKit
import Observation

@Observable
@MainActor
final class StoreKitService {
    static let proProductID = "com.daythread.pro"

    var product: Product?
    var isPurchasing: Bool = false
    var errorMessage: String?

    func fetchProducts() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            product = products.first
        } catch {
            errorMessage = "Could not load product information."
        }
    }

    func purchase(store: TripStore) async {
        guard let product else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified:
                    store.isPro = true
                case .unverified:
                    errorMessage = "Purchase could not be verified."
                }
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases(store: TripStore) async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.proProductID {
                store.isPro = true
            }
        }
    }
}
