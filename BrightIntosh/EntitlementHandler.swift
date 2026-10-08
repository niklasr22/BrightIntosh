//
//  Store.swift
//  LiMeat
//
//  Created by Niklas Rousset on 04.07.24.
//

import StoreKit
import SwiftData
import OSLog


public enum Products: String, CaseIterable {
    case unrestrictedBrightIntosh = "brightintosh_paid"
}

let CACHED_UNRESTRICTED_USER_KEY: String = "cachedUnrestrictedUser"


@MainActor
class EntitlementHandler: ObservableObject {
    private let logger = Logger(
        subsystem: "Store Handler",
        category: "Transaction Processing"
    )
    
    public static let shared = EntitlementHandler()
    
    @Published public var isUnrestrictedUser: Bool = false
    @Published var status: AuthorizationStatus = .pending
    private var transactionUpdatesTask: Task<Void, Never>?
    private var entitlementRevision = 0
    private var revokedTransactionIDs = Set<UInt64>()

    init() {
        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                do {
                    try await self.processTransaction(result)
                } catch {
                    self.logger.error("Transaction update failed: \(error.localizedDescription)")
                }
            }
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func processTransaction(_ result: VerificationResult<Transaction>) async throws {
        let entitled = try await verifyEntitlement(transaction: result)
        guard case .verified(let transaction) = result,
              transaction.productID == Products.unrestrictedBrightIntosh.rawValue else { return }
        if entitled {
            setRestrictionState(.authorizedUnlimited)
        } else {
            revokedTransactionIDs.insert(transaction.id)
            // A refund may revoke the IAP while the legacy paid app still grants access.
            setRestrictionState(.unauthorized)
            _ = try await isUnrestrictedUser()
        }
        await transaction.finish()
    }
    
    func verifyEntitlement(transaction verificationResult: VerificationResult<Transaction>) async throws -> Bool {
   
        let unsafeTransaction = verificationResult.unsafePayloadValue
        
        logger.log("""
        Processing transaction ID \(unsafeTransaction.id) for \
        \(unsafeTransaction.productID)
        """)
        
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
            throw error
        }
        
        return transaction.productID == Products.unrestrictedBrightIntosh.rawValue
            && transaction.revocationDate == nil
            && !revokedTransactionIDs.contains(transaction.id)
            && (transaction.expirationDate.map { $0 > Date.now } ?? true)
    }
    
    func isUnrestrictedUser(refresh: Bool = false) async throws -> Bool {
        if status == .pending && BrightIntoshSettings.getUserDefault(
            key: CACHED_UNRESTRICTED_USER_KEY,
            defaultValue: UserDefaults.standard.bool(forKey: CACHED_UNRESTRICTED_USER_KEY)
        ) {
            setRestrictionState(.authorized)
            print("User was verified previously, authorizing now but validating again")
        }
        let revision = entitlementRevision
        
        var appEntitlementError: Error?
        var legacyAppEntitled = false
        do {
            legacyAppEntitled = try await checkAppEntitlements(refresh: refresh)
        } catch {
            appEntitlementError = error
        }
        guard revision == entitlementRevision else { return isUnrestrictedUser }
        if legacyAppEntitled {
            setRestrictionState(.authorizedUnlimited)
            return true
        }
        
        for await entitlement in Transaction.currentEntitlements {
            if entitlement.unsafePayloadValue.productID == Products.unrestrictedBrightIntosh.rawValue,
               try await self.verifyEntitlement(transaction: entitlement) {
                guard revision == entitlementRevision else { return isUnrestrictedUser }
                setRestrictionState(.authorizedUnlimited)
                if case .verified(let transaction) = entitlement {
                    await transaction.finish()
                }
                print("Checked In App Purchase successfully")
                return true
            }
        }
        // Don't overwrite a purchase or refund delivered while validation was suspended.
        guard revision == entitlementRevision else { return isUnrestrictedUser }
        if let appEntitlementError { throw appEntitlementError }
        print("User is restricted")
        setRestrictionState(.unauthorized)
        return false
    }
    
    func setRestrictionState(_ newStatus: AuthorizationStatus) {
        guard newStatus != .pending else { return }
        entitlementRevision += 1
        self.isUnrestrictedUser = newStatus != .unauthorized
        self.status = newStatus
        BrightIntoshSettings.defaults.setValue(self.isUnrestrictedUser, forKey: CACHED_UNRESTRICTED_USER_KEY)
    }
    
    func checkAppEntitlements(refresh: Bool = false) async throws -> Bool  {
        if BrightIntoshSettings.shared.ignoreAppTransaction {
            return false
        }
        
        let shared = if refresh {
            try await AppTransaction.refresh()
        } else {
            try await AppTransaction.shared
        }
        if case .verified(let appTransaction) = shared {
            print("Original Application Version: \(appTransaction.originalAppVersion)")
            print("Original Purchase Date: \(appTransaction.originalPurchaseDate)")

            if appTransaction.originalAppVersion.isAppVersion(earlierThan: legacyPurchaseEntitlementOriginalPurchaseVersionCutoff) {
                return true
            }
        } else if case .unverified(_, let verificationError) = shared {
            logger.error("App Transaction verification failed: \(verificationError)")
            throw verificationError
        }
        return false
    }
}
