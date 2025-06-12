//
//  Utils.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 01.01.24.
//

import IOKit
import StoreKit
import Cocoa

@MainActor func getXDRDisplays() -> [NSScreen] {
    var xdrScreens: [NSScreen] = []
    for screen in NSScreen.screens {
        if ((isBuiltInScreen(screen: screen) && isDeviceSupported()) || (externalXdrDisplays.contains(screen.localizedName) && !Settings.shared.brightIntoshOnlyOnBuiltIn)) {
            xdrScreens.append(screen)
        }
    }
    return xdrScreens
}

func isBuiltInScreen(screen: NSScreen) -> Bool {
    let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
    let displayId: CGDirectDisplayID = screenNumber as! CGDirectDisplayID
    return CGDisplayIsBuiltin(displayId) != 0
}

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

func connectionAvailable() -> Bool {
    // TODO: check internet connection
    return false;
}

func getDeviceMaxBrightness() -> Float {
    if let device = getModelIdentifier(),
        sdr600nitsDevices.contains(device)
    {
        return 1.535
    }
    return 1.59
}

func getStoreKitErrorMessage(_ error: StoreKitError) -> String {
    let errorDescription = error.errorDescription ?? "N/A"
    let recoverySuggestion = error.recoverySuggestion ?? "N/A"
    return "\(error.localizedDescription) (StoreKitError), \(errorDescription), \(recoverySuggestion)"
}

private func getAppTransaction() async throws -> VerificationResult<AppTransaction>? {
    return try await AppTransaction.shared
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
    do {
        if let sharedAppTransaction = try await getAppTransaction() {
            if case .verified(let appTransaction) = sharedAppTransaction {
                report += "Original Purchase Date: \(appTransaction.originalPurchaseDate)\n"
                report += "Original App Version: \(appTransaction.originalAppVersion)\n"
                report += "Transaction for App Version: \(appTransaction.appVersion)\n"
                report += "Transaction Environment: \(appTransaction.environment.rawValue)\n"
            }
            if case .unverified(_, let verificationError) = sharedAppTransaction {
                report += "Error: App Transaction: \(verificationError.errorDescription ?? "no error description") - \(verificationError.failureReason ?? "no failure reason")\n"
            }
        } else {
            report += "Error: No App Transaction available \n"
        }
    } catch {
        report += "Error: App Transaction could not be fetched: \(error.localizedDescription) \n"
    }

    do {
        let isUnrestricted = try await EntitlementHandler.shared.isUnrestrictedUser()
        report += "Unrestricted user: \(isUnrestricted)\n"
    } catch {
        report += "Error: EntitlementHandler threw an error: \(error.localizedDescription)\n"
    }
    do {
        let trial = try await TrialData.getTrialData()
        report += "Trial:\n - Start Date: \(trial.purchaseDate)\n - Current Date: \(trial.currentDate)\n - Remaining: \(trial.getRemainingDays())\n"
    } catch {
        report += "Error: Trial Data could not be fetched \(error.localizedDescription)\n"
    }
    
    let screens = NSScreen.screens.map{$0.localizedName}
    report += "Screens: \(screens.joined(separator: ", "))\n"
    for screen in NSScreen.screens {
        report += " - Screen \(screen.localizedName): \(screen.frame.width)x\(screen.frame.height)px\n"
    }
    return report
}
