//
//  AppVersion.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 21.05.26.
//

import Foundation

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
