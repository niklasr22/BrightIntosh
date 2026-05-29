//
//  Utils.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 01.01.24.
//

import IOKit
import StoreKit
import Cocoa

struct IncompatibleRunningApp: Equatable {
    let displayName: String
    let bundleIdentifier: String?
}

private struct IncompatibleAppSignature {
    let displayName: String
    let bundleIdentifiers: Set<String>
    let normalizedNames: Set<String>
}

private let incompatibleAppSignatures: [IncompatibleAppSignature] = [
    IncompatibleAppSignature(
        displayName: "f.lux",
        bundleIdentifiers: ["org.herf.Flux"],
        normalizedNames: ["flux", "fluxapp"]
    ),
    IncompatibleAppSignature(
        displayName: "MonitorControl",
        bundleIdentifiers: ["me.guillaumeb.MonitorControl", "app.monitorcontrol.MonitorControl", "app.monitorcontrol.MonitorControlLite"],
        normalizedNames: ["monitorcontrol"]
    ),
    IncompatibleAppSignature(
        displayName: "BetterDisplay",
        bundleIdentifiers: ["com.github.wulkano.BetterDisplay", "pro.betterdisplay.BetterDisplay"],
        normalizedNames: ["betterdisplay", "betterdummy"]
    ),
    IncompatibleAppSignature(
        displayName: "Lunar",
        bundleIdentifiers: ["fyi.lunar.Lunar"],
        normalizedNames: ["lunar"]
    ),
    IncompatibleAppSignature(
        displayName: "Vivid",
        bundleIdentifiers: ["com.getvivid.vivid", "com.getvivid.Vivid"],
        normalizedNames: ["vivid"]
    ),
    IncompatibleAppSignature(
        displayName: "DisplayBuddy",
        bundleIdentifiers: ["com.sids.DisplayBuddy", "com.sids.displaybuddy-setapp"],
        normalizedNames: ["displaybuddy"]
    ),
    IncompatibleAppSignature(
        displayName: "Gamma Control",
        bundleIdentifiers: ["ca.michelf.gamma-control"],
        normalizedNames: ["gammacontrol"]
    ),
    IncompatibleAppSignature(
        displayName: "QuickShade",
        bundleIdentifiers: ["jp.questbeat.Shade"],
        normalizedNames: ["quickshade"]
    ),
    IncompatibleAppSignature(
        displayName: "Iris",
        bundleIdentifiers: ["com.iristech.Iris", "com.iristech.IrisMini"],
        normalizedNames: ["iris", "irismini"]
    ),
]

private func normalizedApplicationName(_ name: String) -> String {
    name
        .lowercased()
        .unicodeScalars
        .filter { CharacterSet.alphanumerics.contains($0) }
        .map(String.init)
        .joined()
}

private func normalizedApplicationCandidates(for app: NSRunningApplication) -> Set<String> {
    var candidates = Set<String>()
    
    if let localizedName = app.localizedName {
        candidates.insert(normalizedApplicationName(localizedName))
    }
    if let bundleIdentifier = app.bundleIdentifier {
        candidates.insert(normalizedApplicationName(bundleIdentifier))
    }
    if let bundleName = app.bundleURL?.deletingPathExtension().lastPathComponent {
        candidates.insert(normalizedApplicationName(bundleName))
    }
    if let executableName = app.executableURL?.deletingPathExtension().lastPathComponent {
        candidates.insert(normalizedApplicationName(executableName))
    }
    
    return candidates
}

@MainActor func runningIncompatibleApps() -> [IncompatibleRunningApp] {
    let currentBundleIdentifier = Bundle.main.bundleIdentifier
    var foundApps: [IncompatibleRunningApp] = []
    
    for app in NSWorkspace.shared.runningApplications {
        guard app.bundleIdentifier != currentBundleIdentifier else { continue }
        
        let bundleIdentifier = app.bundleIdentifier
        let normalizedBundleIdentifier = bundleIdentifier?.lowercased()
        let normalizedCandidates = normalizedApplicationCandidates(for: app)
        
        guard let signature = incompatibleAppSignatures.first(where: { signature in
            if let normalizedBundleIdentifier,
               signature.bundleIdentifiers.contains(where: { $0.lowercased() == normalizedBundleIdentifier }) {
                return true
            }
            if !signature.normalizedNames.isDisjoint(with: normalizedCandidates) {
                return true
            }
            if normalizedCandidates.contains(where: { candidate in
                signature.normalizedNames.contains(where: { candidate.contains($0) })
            }) {
                return true
            }
            return false
        }) else {
            continue
        }
        
        if !foundApps.contains(where: { $0.displayName == signature.displayName }) {
            foundApps.append(IncompatibleRunningApp(
                displayName: signature.displayName,
                bundleIdentifier: bundleIdentifier
            ))
        }
    }
    
    return foundApps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
}

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

@MainActor func isSetupSupported() -> Bool {
    isDeviceSupported() || NSScreen.screens.contains { screen in
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

// Reference bonus gamma for a max EDR value
func getScreenRefGamma(_ screen: NSScreen) -> (Float, Float) {
    if let displayId = screen.displayId, CGDisplayIsBuiltin(displayId) != 0 {
        if let device = getModelIdentifier(),
            sdr600nitsDevices.contains(device)
        {
            return (2.66, 0.50)
        }
        return (3.2, 0.59)
    }
    // Studio/Pro Display XDR
    return (2.66, 0.6)
}

func getStoreKitErrorMessage(_ error: StoreKitError) -> String {
    let errorDescription = error.errorDescription ?? "N/A"
    let recoverySuggestion = error.recoverySuggestion ?? "N/A"
    return "\(error.localizedDescription) (StoreKitError), \(errorDescription), \(recoverySuggestion)"
}

private func getAppTransaction() async throws -> VerificationResult<AppTransaction>? {
    return try await AppTransaction.shared
}

@MainActor
enum SupportReportContext {
    static weak var brightnessManager: BrightnessManager?
}

private let hdrReadyReportThreshold = 1.05

private struct RunningApplicationSnapshot: Comparable {
    let displayName: String
    let bundleIdentifier: String?
    let activationPolicy: NSApplication.ActivationPolicy
    
    var sortKey: String {
        displayName.lowercased()
    }
    
    static func < (lhs: RunningApplicationSnapshot, rhs: RunningApplicationSnapshot) -> Bool {
        lhs.sortKey < rhs.sortKey
    }
}

@MainActor
private func runningApplicationSnapshots() -> [RunningApplicationSnapshot] {
    let currentBundleIdentifier = Bundle.main.bundleIdentifier
    return NSWorkspace.shared.runningApplications.compactMap { app in
        guard app.bundleIdentifier != currentBundleIdentifier else { return nil }
        let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }
        return RunningApplicationSnapshot(
            displayName: name,
            bundleIdentifier: app.bundleIdentifier,
            activationPolicy: app.activationPolicy
        )
    }
    .sorted()
}

@MainActor
private func activationPolicyLabel(_ policy: NSApplication.ActivationPolicy) -> String {
    switch policy {
    case .regular: "regular"
    case .accessory: "accessory"
    case .prohibited: "prohibited"
    @unknown default: "unknown"
    }
}

@MainActor
private func appendSettingsDiagnostics(to report: inout String) {
    let settings = BrightIntoshSettings.shared
    report += "Device / setup:\n"
    report += " - Device in supported list: \(isDeviceSupported())\n"
    report += " - Setup supported (device or external XDR): \(isSetupSupported())\n"
    if let clamshell = isClamshellClosed() {
        report += " - Clamshell closed: \(clamshell)\n"
    } else {
        report += " - Clamshell closed: unknown\n"
    }
    if #available(macOS 12.0, *) {
        report += " - Low Power Mode: \(ProcessInfo.processInfo.isLowPowerModeEnabled)\n"
    }
    
    report += "Settings:\n"
    report += " - Increased brightness active: \(settings.brightintoshActive)\n"
    report += " - Wait for HDR before increasing brightness: \(settings.waitForHDRBeforeIncreasingBrightness)\n"
    report += " - Use alternate brightness backend: \(settings.useAlternateBrightnessBackend)\n"
    report += " - Built-in XDR displays only: \(settings.brightIntoshOnlyOnBuiltIn)\n"
    report += " - Disable when lid closed: \(settings.disableWhenLidClosed)\n"
    report += " - Show HDR retry cooldown notice: \(settings.showHDRRetryCooldownNotice)\n"
    report += " - Show incompatible apps notice: \(settings.showIncompatibleAppsNotice)\n"
}

@MainActor
private func appendDisplayDiagnostics(to report: inout String) {
    let xdrTargets = getXDRDisplays()
    report += "Displays:\n"
    if NSScreen.screens.isEmpty {
        report += " - No screens reported by NSScreen\n"
        return
    }
    
    for screen in NSScreen.screens {
        let displayId = screen.displayId.map(String.init) ?? "N/A"
        let maxEdr = screen.maximumExtendedDynamicRangeColorComponentValue
        let hdrReady = Double(maxEdr) > hdrReadyReportThreshold
        let builtIn = isBuiltInScreen(screen: screen)
        let externalXdr = isExternalXDRDisplay(screen: screen)
        let brightIntoshTarget = xdrTargets.contains { $0.displayId == screen.displayId }
        report += " - \(screen.localizedName) (id \(displayId)): \(Int(screen.frame.width))x\(Int(screen.frame.height))px\n"
        report += "   · max EDR: \(String(format: "%.4f", maxEdr)) (HDR ready if > \(hdrReadyReportThreshold): \(hdrReady))\n"
        report += "   · built-in: \(builtIn), external XDR name match: \(externalXdr), BrightIntosh target: \(brightIntoshTarget)\n"
    }
}

@MainActor
private func appendRunningApplicationsDiagnostics(to report: inout String, maxEntries: Int = 200) {
    let apps = runningApplicationSnapshots()
    
    report += "Running applications (GUI and background agents, not every system process):\n"
    if apps.isEmpty {
        report += " - None\n"
        return
    }
    
    let limited = apps.prefix(maxEntries)
    for app in limited {
        let bundle = app.bundleIdentifier ?? "no bundle id"
        report += " - \(app.displayName) (\(bundle), \(activationPolicyLabel(app.activationPolicy)))\n"
    }
    if apps.count > maxEntries {
        report += " - … truncated (\(apps.count - maxEntries) more not listed)\n"
    }
    report += " - Total listed: \(limited.count) of \(apps.count)\n"
}

func generateReport(includeRunningApplications: Bool = true) async -> String {
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
    
    let incompatibleApps = await MainActor.run {
        runningIncompatibleApps()
    }
    if incompatibleApps.isEmpty {
        report += "Known incompatible running apps: None\n"
    } else {
        report += "Known incompatible running apps:\n"
        for app in incompatibleApps {
            if let bundleIdentifier = app.bundleIdentifier {
                report += " - \(app.displayName) (\(bundleIdentifier))\n"
            } else {
                report += " - \(app.displayName)\n"
            }
        }
    }
    
    await MainActor.run {
        report += "\n"
        appendSettingsDiagnostics(to: &report)
        report += "\n"
        appendDisplayDiagnostics(to: &report)
        report += "\n"
        SupportReportContext.brightnessManager?.appendSupportDiagnostics(to: &report)
        if includeRunningApplications {
            report += "\n"
            appendRunningApplicationsDiagnostics(to: &report)
        }
    }
    return report
}

extension Notification.Name {
    /// Posted when a display enters the HDR retry cooldown. `userInfo["cooldownSeconds"]` is `Int` (starts at 30, increases by 30 per consecutive timeout, capped at 120); `userInfo["displayID"]` is `NSNumber` wrapping `CGDirectDisplayID`.
    static let brightIntoshHDRCooldownDidBegin = Notification.Name("de.brightintosh.hdrCooldownDidBegin")
    /// Posted when that display finishes the sleep and leaves the cooldown wait (before reopening the overlay).
    static let brightIntoshHDRCooldownDidEnd = Notification.Name("de.brightintosh.hdrCooldownDidEnd")
}
