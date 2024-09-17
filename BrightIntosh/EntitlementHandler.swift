//
//  Store.swift
//  LiMeat
//
//  Created by Niklas Rousset on 04.07.24.
//

import StoreKit
import SwiftData
import OSLog


public struct Products {
    static let unrestrictedBrightIntosh = "brightintosh_paid"
}


class EntitlementHandler: ObservableObject {
    private let logger = Logger(
        subsystem: "Store Handler",
        category: "Transaction Processing"
    )
    
    public static let shared = EntitlementHandler()
    
    @Published public var isUnrestrictedUser: Bool = false
    
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
    
    func isUnrestrictedUser(refresh: Bool = false) async -> Bool {
        if !Settings.shared.ignoreAppTransaction && isUnrestrictedUser {
            return true
        }
        
        if await checkAppEntitlements(refresh: refresh) {
            DispatchQueue.main.async {
                self.isUnrestrictedUser = true
            }
            return true
        }
        
        for await entitlement in Transaction.currentEntitlements {
            if entitlement.unsafePayloadValue.productID == Products.unrestrictedBrightIntosh,
               await self.verifyEntitlement(transaction: entitlement) {
                DispatchQueue.main.async {
                    self.isUnrestrictedUser = true
                }
                return true
            }
        }
        DispatchQueue.main.async {
            self.isUnrestrictedUser = false
        }
        return false
    }
    
    func checkAppEntitlements(refresh: Bool = false) async -> Bool {
        if Settings.shared.ignoreAppTransaction {
            return false
        }
            
        do {
            let shared = if refresh {
                try await AppTransaction.refresh()
            } else {
                try await AppTransaction.shared
            }
            if case .verified(let appTransaction) = shared {
                // Hard-code the major version number in which the app's business model changed.
                let newBusinessModelMajorVersion = "3"

                let versionComponents = appTransaction.originalAppVersion.split(separator: ".")
                let originalMajorVersion = versionComponents[0]
                print("Original Application Version: \(appTransaction.originalAppVersion)")
                print("Original Purchase Date: \(appTransaction.originalPurchaseDate)")

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

