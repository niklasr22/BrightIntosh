//
//  Trial.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 06.09.24.
//

import Foundation
import StoreKit

enum TrialError: Error {
    case error
    case noActualTimeError
}

extension Date {
    static func getActualTime() async -> Date {
#if STORE
        do {
            let (data, _) = try await URLSession.shared.data(from: BrightIntoshUrls.time)
            if let timestampString = String(data: data, encoding: .utf8),
                let timestamp = TimeInterval(timestampString) {
                let date = Date(timeIntervalSince1970: timestamp)
                print("Received date \(date)")
                return date
            } else {
                throw TrialError.noActualTimeError
            }
        } catch {
            return Date.now
        }
#else
        return Date.now
#endif
    }
}

public struct TrialData: Sendable {
    let purchaseDate: Date
    let currentDate: Date
    
    func getRemainingDays() -> Int {
        if let expirationDate = getExpirationDate(), currentDate < expirationDate {
            return Calendar.current.dateComponents([.year, .month, .day], from: currentDate, to: expirationDate).day ?? 0
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
                let originalDate = appTransaction.originalPurchaseDate
                let currentDate = await Date.getActualTime()
                return TrialData(purchaseDate: originalDate, currentDate: currentDate)
            }
        } catch {
            throw TrialError.error
        }
        throw TrialError.error
    }
}

@MainActor
public class TrialHandler: ObservableObject {
    public static let shared = TrialHandler()
    
    @Published var status: AuthorizationStatus = .pending
    
    private func loadTrialStatus() async -> AuthorizationStatus {
        guard !BrightIntoshSettings.getUserDefault(key: "trialExpired", defaultValue: false) else {
            return .unauthorized
        }
        do {
            let stillEntitledToTrial = (try await TrialData.getTrialData()).stillEntitled()
            if !stillEntitledToTrial {
                UserDefaults.standard.setValue(true, forKey: "trialExpired")
            }
            return stillEntitledToTrial ? .authorized : .unauthorized
        } catch {
            return .unauthorized
        }
    }
    
    func updateTrialState() async -> AuthorizationStatus {
        status = await loadTrialStatus()
        return status
    }
}
