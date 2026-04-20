//
//  Utils.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 01.01.24.
//

import IOKit
import StoreKit
import Cocoa


enum TimeoutError: Error {
    case timeout
}

private func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            let nanoseconds = UInt64(seconds * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
            throw TimeoutError.timeout
        }

        let result = try await group.next()
        group.cancelAll()

        guard let result else {
            throw TimeoutError.timeout
        }
        return result
    }
}

private func timeoutErrorMessage(_ context: String, seconds: Double) -> String {
    "\(context) timed out after \(Int(seconds))s"
}


func isExternalXDRDisplay(screen: NSScreen) -> Bool {
    externalXdrDisplays.contains(screen.localizedName)
}

@MainActor func isScreenSupportedForBrightIntosh(
    screen: NSScreen,
    respectBuiltInPreference: Bool = true
) -> Bool {
    if isBuiltInScreen(screen: screen) && isDeviceSupported() {
        return true
    }

    if isExternalXDRDisplay(screen: screen) {
        return !respectBuiltInPreference || !BrightIntoshSettings.shared.brightIntoshOnlyOnBuiltIn
    }

    return false
}

@MainActor func hasAnySupportedDisplayConnected() -> Bool {
    NSScreen.screens.contains { screen in
        isScreenSupportedForBrightIntosh(screen: screen, respectBuiltInPreference: false)
    }
}

@MainActor func getXDRDisplays() -> [NSScreen] {
    NSScreen.screens.filter { screen in
        isScreenSupportedForBrightIntosh(screen: screen)
    }
}

func isBuiltInScreen(screen: NSScreen) -> Bool {
    let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
    let displayId: CGDirectDisplayID = screenNumber as! CGDirectDisplayID
    return CGDisplayIsBuiltin(displayId) != 0
}

func isClamshellClosed() -> Bool? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard service != 0 else {
        return nil
    }
    defer {
        IOObjectRelease(service)
    }

    let clamshellState = IORegistryEntryCreateCFProperty(
        service,
        "AppleClamshellState" as CFString,
        kCFAllocatorDefault,
        0
    )?.takeRetainedValue()

    if let value = clamshellState as? Bool {
        return value
    }
    if let number = clamshellState as? NSNumber {
        return number.boolValue
    }
    return nil
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
    let timeoutSeconds = 3.0
    var report = "BrightIntosh Report:\n"
    report += "OS-Version: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
    #if STORE
        report += "Version: BrightIntosh SE v\(appVersion)\n"
    #else
        report += "Version: BrightIntosh v\(appVersion)\n"
    #endif
    report += "Model Identifier: \(getModelIdentifier() ?? "N/A")\n"
    do {
        if let sharedAppTransaction = try await (withTimeout(seconds: timeoutSeconds) {
            try await getAppTransaction()
        }) {
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
    } catch TimeoutError.timeout {
        report += "Error: \(timeoutErrorMessage("App Transaction lookup", seconds: timeoutSeconds))\n"
    } catch {
        report += "Error: App Transaction could not be fetched: \(error.localizedDescription) \n"
    }

    do {
        let isUnrestricted = try await withTimeout(seconds: timeoutSeconds) {
            try await EntitlementHandler.shared.isUnrestrictedUser()
        }
        report += "Unrestricted user: \(isUnrestricted)\n"
    } catch TimeoutError.timeout {
        report += "Error: \(timeoutErrorMessage("Entitlement check", seconds: timeoutSeconds))\n"
    } catch {
        report += "Error: EntitlementHandler threw an error: \(error.localizedDescription)\n"
    }
    do {
        let trial = try await withTimeout(seconds: timeoutSeconds) {
            try await TrialData.getTrialData()
        }
        report += "Trial:\n - Start Date: \(trial.purchaseDate)\n - Current Date: \(trial.currentDate)\n - Remaining: \(trial.getRemainingDays())\n"
    } catch TimeoutError.timeout {
        report += "Error: \(timeoutErrorMessage("Trial data lookup", seconds: timeoutSeconds))\n"
    } catch {
        report += "Error: Trial Data could not be fetched \(error.localizedDescription)\n"
    }
    
    report += "Screens:\n"
    for screen in NSScreen.screens {
        report += " - \(screen.localizedName): \(screen.frame.width)x\(screen.frame.height)px\n"
    }
    return report
}

extension Notification.Name {
    /// Posted when a display enters the HDR retry cooldown. `userInfo["cooldownSeconds"]` is `Int` (starts at 30, increases by 30 per consecutive timeout, capped at 120); `userInfo["displayID"]` is `NSNumber` wrapping `CGDirectDisplayID`.
    static let brightIntoshHDRCooldownDidBegin = Notification.Name("de.brightintosh.hdrCooldownDidBegin")
    /// Posted when that display finishes the sleep and leaves the cooldown wait (before reopening the overlay).
    static let brightIntoshHDRCooldownDidEnd = Notification.Name("de.brightintosh.hdrCooldownDidEnd")
}
