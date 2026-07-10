//
//  AppVersion.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 21.05.26.
//

import Foundation

#if STORE
    import StoreKit
#endif

let brightnessSliderRemovalOriginalPurchaseVersionCutoff = "6.0.0"
let legacyPurchaseEntitlementOriginalPurchaseVersionCutoff = "3.0.0"

struct AppVersion: Comparable {
    private let components: [Int]

    init(_ version: String) {
        components = version.split(separator: ".").map { Int($0) ?? 0 }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let componentCount = max(lhs.components.count, rhs.components.count)

        for index in 0..<componentCount {
            let lhsComponent = index < lhs.components.count ? lhs.components[index] : 0
            let rhsComponent = index < rhs.components.count ? rhs.components[index] : 0

            if lhsComponent != rhsComponent {
                return lhsComponent < rhsComponent
            }
        }

        return false
    }
}

extension String {
    func isAppVersion(earlierThan otherVersion: String) -> Bool {
        AppVersion(self) < AppVersion(otherVersion)
    }
}

func originalPurchaseVersionIsEarlierThan(_ cutoffVersion: String) async -> Bool {
    #if STORE
        do {
            let shared = try await AppTransaction.shared
            if case .verified(let appTransaction) = shared {
                return appTransaction.originalAppVersion.isAppVersion(earlierThan: cutoffVersion)
            }
        } catch {
            return false
        }
    #endif

    return false
}

@MainActor
func configureFineGrainedBrightnessControlDefaultIfNeeded() async {
    let migrationKey = "configuredFineGrainedBrightnessControlDefault"
    guard !BrightIntoshSettings.defaults.bool(forKey: migrationKey) else {
        return
    }
    
    if await originalPurchaseVersionIsEarlierThan(brightnessSliderRemovalOriginalPurchaseVersionCutoff) {
        BrightIntoshSettings.shared.fineGrainedBrightnessControl = true
    }
    
    BrightIntoshSettings.defaults.set(true, forKey: migrationKey)
}
