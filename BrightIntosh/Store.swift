//
//  Store.swift
//  LiMeat
//
//  Created by Niklas Rousset on 04.07.24.
//

import Foundation
import StoreKit
import OSLog
import SwiftData


struct Products {
    static let unrestrictedBrightIntosh = "brightintosh_paid"
}

class StoreManager: NSObject, ObservableObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    @Published var products: [SKProduct] = []
    @Published var purchasedProductIdentifiers: Set<String> = []
    
    override init() {
        super.init()
        SKPaymentQueue.default().add(self)
        fetchProducts()
    }
    
    func fetchProducts() {
        let request = SKProductsRequest(productIdentifiers: [Products.unrestrictedBrightIntosh])
        request.delegate = self
        request.start()
    }
    
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        DispatchQueue.main.async {
            self.products = response.products
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
        purchasedProductIdentifiers.insert(transaction.payment.productIdentifier)
    }
    
    private func failed(transaction: SKPaymentTransaction) {
        if let error = transaction.error as NSError? {
            print("Transaction failed: \(error.localizedDescription)")
        }
        SKPaymentQueue.default().finishTransaction(transaction)
    }
    
    private func restore(transaction: SKPaymentTransaction) {
        SKPaymentQueue.default().finishTransaction(transaction)
        purchasedProductIdentifiers.insert(transaction.payment.productIdentifier)
    }
    
    func restorePurchases() {
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
}


actor StoreHandler {
    private let logger = Logger(
        subsystem: "Store Handler",
        category: "Transaction Processing"
    )
    
    private var updatesTask: Task<Void, Never>?
    
    public static let shared = StoreHandler()
    
    func verifyEntitlement(transaction verificationResult: VerificationResult<Transaction>) async -> Bool {
        do {
            let unsafeTransaction = verificationResult.unsafePayloadValue
            logger.log("""
            Processing transaction ID \(unsafeTransaction.id) for \
            \(unsafeTransaction.productID)
            """)
        }
        
        let transaction: Transaction
        switch verificationResult {
        case .verified(let t):
            logger.debug("""
            (Entitlement) Transaction ID \(t.id) for \(t.productID) is verified
            """)
            transaction = t
        case .unverified(let t, let error):
            // Log failure and ignore unverified transactions
            logger.error("""
            (Entitlement) Transaction ID \(t.id) for \(t.productID) is unverified: \(error)
            """)
            return false
        }
        
        logger.info("User is entitled to have the product \(transaction.productID)")
        return true
    }
    
    func isUnrestrictedUser() async -> Bool {
        if await checkAppEntitlements() {
            return true
        }
        
        for await entitlement in Transaction.currentEntitlements {
            if entitlement.unsafePayloadValue.productID == Products.unrestrictedBrightIntosh,
               await self.verifyEntitlement(transaction: entitlement) {
                return true
            }
        }
        return false
    }
    
    func checkAppEntitlements() async -> Bool {
        do {
            // Get the appTransaction.
            let shared = try await AppTransaction.shared
            if case .verified(let appTransaction) = shared {
                // Hard-code the major version number in which the app's business model changed.
                let newBusinessModelMajorVersion = "3"


                // Get the major version number of the version the customer originally purchased.
                let versionComponents = appTransaction.originalAppVersion.split(separator: ".")
                let originalMajorVersion = versionComponents[0]
                print(originalMajorVersion)
                print(appTransaction.debugDescription)

                if originalMajorVersion < newBusinessModelMajorVersion {
                    return true
                }
            }
        } catch {
            logger.error("Fetching app transaction failed")
        }
        return false
    }
}

