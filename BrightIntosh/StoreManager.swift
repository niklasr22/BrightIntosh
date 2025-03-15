//
//  StoreManager.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 08.09.24.
//

import StoreKit

class StoreManager: NSObject, ObservableObject, SKPaymentTransactionObserver {
    @Published var products: [SKProduct] = []
    
    override init() {
        super.init()
        SKPaymentQueue.default().add(self)
    }
    
    func fetchProducts() async -> [Product] {
        do {
            let availableProducts = Products.allCases.map { $0.rawValue }
            return try await Product.products(for: availableProducts)
        } catch {
            return []
        }
    }
    
    @MainActor
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        let newProducts = response.products as [SKProduct]
        Task { @MainActor [newProducts] in
            self.products = newProducts
        }
    }
    
    func purchase(product: SKProduct) {
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                complete(transaction: transaction)
            case .failed:
                failed(transaction: transaction)
            case .restored:
                restore(transaction: transaction)
            case .deferred, .purchasing:
                break
            @unknown default:
                break
            }
        }
    }
    
    private func complete(transaction: SKPaymentTransaction) {
        SKPaymentQueue.default().finishTransaction(transaction)
        Task {
            _ = await EntitlementHandler.shared.isUnrestrictedUser()
        }
    }
    
    private func failed(transaction: SKPaymentTransaction) {
        if let error = transaction.error as NSError? {
            print("Transaction failed: \(error.localizedDescription)")
        }
    }
    
    private func restore(transaction: SKPaymentTransaction) {
        SKPaymentQueue.default().finishTransaction(transaction)
        Task {
            _ = await EntitlementHandler.shared.isUnrestrictedUser()
        }
    }
    
    func restorePurchases() {
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
}
