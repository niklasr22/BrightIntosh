//
//  Trial.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 06.09.24.
//

import StoreKit

enum TrialError: Error {
    case error
}

public struct TrialData {
    let purchaseDate: Date
    let currentDate: Date
    
    func getRemainingDays() -> Int {
        
        if let expirationDate = getExpirationDate(), currentDate < expirationDate {
            return Calendar.current.dateComponents([.year, .month, .day, .hour], from: currentDate, to: expirationDate).day ?? 0
        }
        return 0
    }
    
    private func getExpirationDate() -> Date? {
        return Calendar.current.date(byAdding: .day, value: 3, to: purchaseDate)
    }
    
    func stillEntitled() -> Bool {
        if let expirationDate = getExpirationDate() {
            return currentDate < expirationDate
        }
        return false
    }
    
    static func getTrialData() async throws -> TrialData {
        do {
            let shared = try await AppTransaction.shared
            if case .verified(let appTransaction) = shared {
                return TrialData(purchaseDate: appTransaction.originalPurchaseDate, currentDate: appTransaction.signedDate)
            }
        } catch {
            throw TrialError.error
        }
        throw TrialError.error
    }
}
