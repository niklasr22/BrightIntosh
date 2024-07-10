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
        products = response.products
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
    
    private(set) static var shared: StoreHandler!
    
    static func createSharedInstance() {
        shared = StoreHandler()
    }
    
    func process(transaction verificationResult: VerificationResult<Transaction>) async {
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
            Transaction ID \(t.id) for \(t.productID) is verified
            """)
            transaction = t
        case .unverified(let t, let error):
            // Log failure and ignore unverified transactions
            logger.error("""
            Transaction ID \(t.id) for \(t.productID) is unverified: \(error)
            """)
            return
        }

        if case .nonConsumable = transaction.productType {
            await transaction.finish()
            handleTransaction(transaction: transaction)
        }
    }
    
    func checkForUnfinishedTransactions() async {
        logger.debug("Checking for unfinished transactions")
        for await transaction in Transaction.unfinished {
            let unsafeTransaction = transaction.unsafePayloadValue
            logger.log("""
            Processing unfinished transaction ID \(unsafeTransaction.id) for \
            \(unsafeTransaction.productID)
            """)
            Task.detached(priority: .background) {
                await self.process(transaction: transaction)
            }
        }
        logger.debug("Finished checking for unfinished transactions")
    }
    
    func observeTransactionUpdates() {
        self.updatesTask = Task { [weak self] in
            self?.logger.debug("Observing transaction updates")
            for await update in Transaction.updates {
                guard let self else { break }
                await self.process(transaction: update)
            }
        }
    }
    
    func processEntitlement(transaction verificationResult: VerificationResult<Transaction>) async {
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
            return
        }
        
        logger.info("User is entitled to have the product \(transaction.productID)")
        handleTransaction(transaction: transaction)
    }
    
    func checkForEntitlements() {
        self.updatesTask = Task { [weak self] in
            self?.logger.debug("Observing transaction updates")
            for await entitlement in Transaction.currentEntitlements {
                guard let self else { break }
                await self.processEntitlement(transaction: entitlement)
            }
        }
    }
    
}


func handleTransaction(transaction: Transaction) {
    if transaction.productID == Products.unrestrictedBrightIntosh {
       // Settings.shared.entitledToUnrestrictedUse = true
    }
}

@available(macOS 13.0, *)
func checkAppEntitlements() async {
    do {
        // Get the appTransaction.
        let shared = try await AppTransaction.shared
        if case .verified(let appTransaction) = shared {
            // Hard-code the major version number in which the app's business model changed.
            let newBusinessModelMajorVersion = "2"


            // Get the major version number of the version the customer originally purchased.
            let versionComponents = appTransaction.originalAppVersion.split(separator: ".")
            let originalMajorVersion = versionComponents[0]
            print(originalMajorVersion)
            print(appTransaction.debugDescription)

            if originalMajorVersion < newBusinessModelMajorVersion {
                Settings.shared.entitledToUnrestrictedUse = true
            }
        }
    }
    catch {
        // Handle errors.
        print("woopsie")
    }
    
    for await result in Transaction.currentEntitlements {
        if case .verified(let transaction) = result {
            handleTransaction(transaction: transaction)
        }
    }
}

