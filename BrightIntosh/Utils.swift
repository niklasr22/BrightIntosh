//
//  Utils.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 01.01.24.
//

import Foundation
import IOKit
import StoreKit

func getModelIdentifier() -> String? {
    let service = IOServiceGetMatchingService(
        kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    var modelIdentifier: String?
    if let modelData = IORegistryEntryCreateCFProperty(
        service, "model" as CFString, kCFAllocatorDefault, 0
    ).takeRetainedValue() as? Data {
        modelIdentifier = String(data: modelData, encoding: .utf8)?.trimmingCharacters(
            in: .controlCharacters)
    }

    IOObjectRelease(service)
    return modelIdentifier
}

func isDeviceSupported() -> Bool {
    if let device = getModelIdentifier(), supportedDevices.contains(device) {
        return true
    }
    return false
}

func getDeviceMaxBrightness() -> Float {
    if let device = getModelIdentifier(),
        sdr600nitsDevices.contains(device)
    {
        return 1.535
    }
    return 1.59
}

private func getAppTransaction() async -> VerificationResult<AppTransaction>? {
    do {
        let shared = try await AppTransaction.shared
        return shared
    } catch {
        print("Fetching app transaction failed")
    }
    return nil
}

func generateReport() async -> String {
    var report = "BrightIntosh Report:\n"
    report += "OS-Version: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
    #if STORE
        report += "Version: BrightIntosh SE v\(appVersion)\n"
    #else
        report += "Version: BrightIntosh v\(appVersion)\n"
    #endif
    report += "Model Identifier: \(getModelIdentifier() ?? "N/A")\n"
    if let sharedAppTransaction = await getAppTransaction() {
        if case .verified(let appTransaction) = sharedAppTransaction {
            report += "Original Purchase Date: \(appTransaction.originalPurchaseDate)\n"
            report += "Original App Version: \(appTransaction.originalAppVersion)\n"
            report += "Transaction for App Version: \(appTransaction.appVersion)\n"
            report += "Transaction Environment: \(appTransaction.environment.rawValue)\n"
        }
        if case .unverified(_, let verificationError) = sharedAppTransaction {
            report +=
                "Error: App Transaction: \(verificationError.errorDescription ?? "no error description") - \(verificationError.failureReason ?? "no failure reason")\n"
        }
    } else {
        report += "Error: App Transaction could not be fetched \n"
    }

    let isUnrestricted = await EntitlementHandler.shared.isUnrestrictedUser()
    report += "Unrestricted user: \(isUnrestricted)\n"
    do {
        let trial = try await TrialData.getTrialData()
        report +=
            "Trial:\n - Start Date: \(trial.purchaseDate)\n - Current Date: \(trial.currentDate)\n - Remaining: \(trial.getRemainingDays())\n"
    } catch {
        report += "Error: Trial Data could not be fetched\n"
    }
    report += "Screens: \(NSScreen.screens.map{$0.localizedName}.joined(separator: ", "))\n"
    for screen in NSScreen.screens {
        report += " - Screen \(NSScreen.screens.map{$0.localizedName}): \(screen.frame.width)x\(screen.frame.height)px\n"
    }
    return report
}
