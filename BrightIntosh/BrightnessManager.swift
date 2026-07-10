//
//  BrightnessManager.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 01.10.23.
//

import Foundation
import Cocoa
import Combine
import CoreGraphics

extension NSScreen {
    var displayId: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
}

@MainActor
protocol BrightnessManaging: AnyObject {
    func appendSupportDiagnostics(to report: inout String)
}

@MainActor
class BrightnessManager: BrightnessManaging {
    
    var brightnessTechnique: BrightnessTechnique?
    var screens: [NSScreen] = []
    var xdrScreens: [NSScreen] = []
    var enabled: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private var screenUpdateDebounceTask: Task<Void, Never>?
    
    init() {
        setBrightnessTechnique()
        screens = NSScreen.screens
        xdrScreens = getXDRDisplays()
        
        if BrightIntoshSettings.shared.brightintoshActive {
            if shouldDisableForClosedLid(currentScreens: screens) {
                BrightIntoshSettings.shared.brightintoshActive = false
            } else {
                activateSafely()
            }
        }
        
        // Observe displays
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParameters(notification:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )


        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleScreensSleep(notification:)),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeFromSleep(notification:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep(notification:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        // Observe entitlement
        Authorizer.shared.$status.sink { newStatus in
            if newStatus == .unauthorized && BrightIntoshSettings.shared.brightintoshActive {
                BrightIntoshSettings.shared.brightintoshActive = false
            }
        }.store(in: &cancellables)
        
        // Add settings listeners
        BrightIntoshSettings.shared.addListener(setting: "brightintoshActive") {
            if BrightIntoshSettings.shared.brightintoshActive {
                self.activateSafely()
            } else if self.enabled {
                self.brightnessTechnique?.disable()
            }
        }
        
        BrightIntoshSettings.shared.addListener(setting: "brightIntoshOnlyOnBuiltIn") {
            self.handlePotentialScreenUpdate()
        }

        BrightIntoshSettings.shared.addListener(setting: "disableWhenLidClosed") {
            self.handlePotentialScreenUpdate()
        }
        
        BrightIntoshSettings.shared.addListener(setting: "useAlternateBrightnessBackend") {
            self.setBrightnessTechnique()
        }
        
        BrightIntoshSettings.shared.addListener(setting: "waitForHDRBeforeIncreasingBrightness") {
            self.refreshActiveBrightnessTechnique()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    func activateSafely() {
        if Authorizer.shared.isAllowed() {
            self.enabled = true
            self.enableExtraBrightness()
        } else {
            BrightIntoshSettings.shared.brightintoshActive = false
        }
    }
    
    func setBrightnessTechnique() {
        brightnessTechnique?.disable()
        let shouldUseAlternateBackend = BrightIntoshSettings.shared.useAlternateBrightnessBackend
        if shouldUseAlternateBackend {
            brightnessTechnique = MultiplyingOverlayTechnique()
        } else {
            brightnessTechnique = GammaTechnique()
        }
        print("Activated \(shouldUseAlternateBackend ? "alternate" : "standard") brightness backend")
        
        if enabled && BrightIntoshSettings.shared.brightintoshActive {
            enableExtraBrightness()
        }
    }
    
    @MainActor @objc func handleScreenParameters(notification: Notification) {
        scheduleDebouncedScreenUpdate()
    }
    
    @MainActor @objc func handleWakeFromSleep(notification: Notification) {
        guard BrightIntoshSettings.shared.brightintoshActive && enabled else {
            return
        }
        if shouldDisableForClosedLid(currentScreens: NSScreen.screens) {
            BrightIntoshSettings.shared.brightintoshActive = false
            return
        }
        print("Restoring color sync settings after wake from sleep")
        CGDisplayRestoreColorSyncSettings()
        enableExtraBrightness()
        scheduleDebouncedScreenUpdate()
    }
    
    @MainActor @objc func handleScreensSleep(notification: Notification) {
        print("Restoring color sync settings as screens sleep")
        CGDisplayRestoreColorSyncSettings()
    }
    
    @MainActor @objc func handleWillSleep(notification: Notification) {
        guard brightnessTechnique?.isEnabled == true else {
            return
        }
        print("Disabling brightness technique before system sleep")
        brightnessTechnique?.disable()
    }
    
    @MainActor func handlePotentialScreenUpdate() {
        let newScreens = NSScreen.screens
        let newXdrDisplays = getXDRDisplays()
        var changedScreens = newScreens.count != screens.count || newXdrDisplays.count != xdrScreens.count
        let screenWasRemoved = newScreens.count < screens.count || newXdrDisplays.count < xdrScreens.count
        let screenWasAdded = newScreens.count > screens.count || newXdrDisplays.count > xdrScreens.count
        if !changedScreens {
            for screen in screens {
                let sameScreen = newScreens.filter({$0.displayId == screen.displayId }).first
                if sameScreen?.frame.origin != screen.frame.origin {
                    changedScreens = true;
                    break
                }
            }
        }
        
        if changedScreens {
            print("Screen setup changed")
            screens = newScreens
            xdrScreens = newXdrDisplays
        }

        if BrightIntoshSettings.shared.brightintoshActive && shouldDisableForClosedLid(currentScreens: newScreens) {
            BrightIntoshSettings.shared.brightintoshActive = false
            return
        }
        guard enabled else {
            return
        }
        
        if !newScreens.isEmpty {
            if let brightnessTechnique = brightnessTechnique, BrightIntoshSettings.shared.brightintoshActive {
                if changedScreens && screenWasRemoved {
                    print("Screen removed, updating active displays")
                    brightnessTechnique.screenUpdate(screens: newXdrDisplays)
                } else if changedScreens && screenWasAdded && brightnessTechnique.isEnabled {
                    print("Screen attached, enabling increased brightness immediately")
                    brightnessTechnique.screenUpdate(screens: newXdrDisplays)
                } else if changedScreens && brightnessTechnique.isEnabled {
                    print("Changed screen setup")
                    brightnessTechnique.screenUpdate(screens: newXdrDisplays)
                } else if brightnessTechnique.isEnabled {
                    brightnessTechnique.adjustBrightness()
                }
            }
        } else {
            print("Disabling")
            self.brightnessTechnique?.disable()
        }
    }
    
    @MainActor
    private func enableExtraBrightness() {
        self.brightnessTechnique?.enable()
    }
    
    @MainActor
    private func refreshActiveBrightnessTechnique() {
        guard enabled, BrightIntoshSettings.shared.brightintoshActive else {
            return
        }
        
        xdrScreens = getXDRDisplays()
        brightnessTechnique?.screenUpdate(screens: xdrScreens)
    }
    
    @MainActor
    private func scheduleDebouncedScreenUpdate() {
        screenUpdateDebounceTask?.cancel()
        screenUpdateDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            
            guard !Task.isCancelled else {
                return
            }
            
            self.handlePotentialScreenUpdate()
        }
    }

    @MainActor
    func appendSupportDiagnostics(to report: inout String) {
        report += "Brightness manager:\n"
        report += " - Manager enabled: \(enabled)\n"
        report += " - Increased brightness setting: \(BrightIntoshSettings.shared.brightintoshActive)\n"
        if let technique = brightnessTechnique {
            report += " - Active technique: \(String(describing: type(of: technique)))\n"
            if let hdrTechnique = technique as? HDRLifecycleBrightnessTechnique {
                hdrTechnique.appendHDRSupportDiagnostics(to: &report)
            }
        } else {
            report += " - Active technique: none\n"
        }
    }
    
    @MainActor
    private func shouldDisableForClosedLid(currentScreens: [NSScreen]) -> Bool {
        guard BrightIntoshSettings.shared.disableWhenLidClosed else {
            return false
        }
        if let clamshellClosed = isClamshellClosed() {
            return clamshellClosed
        }
        // Fallback if clamshell state is unavailable.
        return !currentScreens.isEmpty && !currentScreens.contains(where: { isBuiltInScreen(screen: $0) })
    }
    
}


/**
 The compatibility brightness manager is similar to the one used in v5.0.1
 */
@MainActor
final class CompatibilityBrightnessManager: BrightnessManaging {
    
    private var brightnessTechnique = CompatibilityGammaTechnique()
    private var screens: [NSScreen] = []
    private var xdrScreens: [NSScreen] = []
    private var enabled: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private var displayRemovalReenableTask: Task<Void, Never>?
    private let displayStabilizationDelay: Duration = .seconds(5)
    private let postEnableScreenParameterSuppression: TimeInterval = 2
    private var suppressAggressiveScreenParameterResetUntil: Date = .distantPast
    
    nonisolated private static let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = { displayId, flags, userInfo in
        guard let userInfo else {
            print("Reconfiguration callback ignored without userInfo: \(flags)")
            return
        }
        
        print("Reconfiguration callback triggered \(flags.contains(.beginConfigurationFlag) ? "begin" : "end") flags=\(flags)")
        
        let manager = Unmanaged<CompatibilityBrightnessManager>.fromOpaque(userInfo).takeUnretainedValue()
        if flags.contains(.beginConfigurationFlag) {
            CGDisplayRestoreColorSyncSettings()
            Task { @MainActor in
                manager.handleDisplayReconfigurationWillBegin(displayId: displayId, flags: flags)
            }
        } else {
            Task { @MainActor in
                manager.handleDisplayReconfigurationDidEnd()
            }
        }
    }
    
    init() {
        screens = NSScreen.screens
        xdrScreens = getXDRDisplays()
        
        if BrightIntoshSettings.shared.brightintoshActive {
            if shouldDisableForClosedLid(currentScreens: screens) {
                BrightIntoshSettings.shared.brightintoshActive = false
            } else {
                activateSafely()
            }
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParameters(notification:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensWake(notification:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleScreensSleep(notification:)),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep(notification:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        
        Authorizer.shared.$status.sink { newStatus in
            if newStatus == .unauthorized && BrightIntoshSettings.shared.brightintoshActive {
                BrightIntoshSettings.shared.brightintoshActive = false
            }
        }.store(in: &cancellables)
        
        BrightIntoshSettings.shared.addListener(setting: "brightintoshActive") {
            if BrightIntoshSettings.shared.brightintoshActive {
                self.activateSafely()
            } else if self.enabled {
                self.brightnessTechnique.disable()
            }
        }
        
        BrightIntoshSettings.shared.addListener(setting: "brightIntoshOnlyOnBuiltIn") {
            self.handlePotentialScreenUpdate()
        }
        
        BrightIntoshSettings.shared.addListener(setting: "disableWhenLidClosed") {
            self.handlePotentialScreenUpdate()
        }
        
        CGDisplayRegisterReconfigurationCallback(
            Self.displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        
        print("Activated compatibility brightness manager")
    }
    
    deinit {
        let brightnessTechnique = brightnessTechnique
        displayRemovalReenableTask?.cancel()
        CGDisplayRemoveReconfigurationCallback(
            Self.displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        Task { @MainActor in
            brightnessTechnique.disable()
        }
    }
    
    private func activateSafely() {
        if Authorizer.shared.isAllowed() {
            enabled = true
            enableExtraBrightness()
        } else {
            BrightIntoshSettings.shared.brightintoshActive = false
        }
    }
    
    @MainActor @objc private func handleScreenParameters(notification: Notification) {
        guard Date() >= suppressAggressiveScreenParameterResetUntil else {
            print("Ignoring compatibility screen parameter reset shortly after enabling brightness")
            handlePotentialScreenUpdate()
            return
        }
        
        aggressivelyResetCompatibilityBrightness(reason: "screen parameters changed")
        scheduleReenableAfterDisplayStabilization(reason: "screen parameters changed")
    }
    
    @MainActor @objc private func screensWake(notification: Notification) {
        print("Compatibility brightness wake up \(notification.name)")
        guard BrightIntoshSettings.shared.brightintoshActive && enabled else {
            return
        }
        if shouldDisableForClosedLid(currentScreens: NSScreen.screens) {
            aggressivelyResetCompatibilityBrightness(reason: "wake while lid is closed")
            BrightIntoshSettings.shared.brightintoshActive = false
            return
        }
        CGDisplayRestoreColorSyncSettings()
        aggressivelyResetCompatibilityBrightness(reason: "wake before delayed re-enable")
        scheduleReenableAfterDisplayStabilization(reason: "wake")
    }
    
    @MainActor @objc private func handleScreensSleep(notification: Notification) {
        aggressivelyResetCompatibilityBrightness(reason: "screens sleep")
    }
    
    @MainActor @objc private func handleWillSleep(notification: Notification) {
        aggressivelyResetCompatibilityBrightness(reason: "system will sleep")
    }
    
    @MainActor private func handleDisplayReconfigurationWillBegin(displayId: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        displayRemovalReenableTask?.cancel()
        
        aggressivelyResetCompatibilityBrightness(reason: "display \(displayId) reconfiguration begin flags=\(flags)")
    }
    
    @MainActor private func handleDisplayReconfigurationDidEnd() {
        scheduleReenableAfterDisplayStabilization(reason: "display reconfiguration ended")
    }
    
    @MainActor private func scheduleReenableAfterDisplayStabilization(reason: String) {
        displayRemovalReenableTask?.cancel()
        print("Waiting \(displayStabilizationDelay) before re-enabling compatibility brightness after \(reason)")
        
        displayRemovalReenableTask = Task { @MainActor in
            try? await Task.sleep(for: self.displayStabilizationDelay)
            guard !Task.isCancelled,
                  self.enabled,
                  BrightIntoshSettings.shared.brightintoshActive else {
                return
            }
            
            let activeScreens = NSScreen.screens
            let activeXdrScreens = getXDRDisplays()
            self.screens = activeScreens
            self.xdrScreens = activeXdrScreens
            
            guard !activeXdrScreens.isEmpty else {
                print("No compatible displays left after display removal")
                return
            }
            
            if self.shouldDisableForClosedLid(currentScreens: activeScreens) {
                self.aggressivelyResetCompatibilityBrightness(reason: "display reconfiguration ended while lid is closed")
                BrightIntoshSettings.shared.brightintoshActive = false
                return
            }
            
            print("Re-enabling compatibility brightness after display reconfiguration")
            CGDisplayRestoreColorSyncSettings()
            self.enableExtraBrightness()
            self.handlePotentialScreenUpdate()
        }
    }
    
    @MainActor private func handlePotentialScreenUpdate() {
        let newScreens = NSScreen.screens
        let newXdrDisplays = getXDRDisplays()
        var changedScreens = newScreens.count != screens.count || newXdrDisplays.count != xdrScreens.count
        if !changedScreens {
            for screen in screens {
                let sameScreen = newScreens.filter({ $0.displayId == screen.displayId }).first
                if sameScreen?.frame.origin != screen.frame.origin {
                    changedScreens = true
                    break
                }
            }
        }
        
        if changedScreens {
            print("Compatibility brightness screen setup changed")
            screens = newScreens
            xdrScreens = newXdrDisplays
        }
        
        if BrightIntoshSettings.shared.brightintoshActive && shouldDisableForClosedLid(currentScreens: newScreens) {
            aggressivelyResetCompatibilityBrightness(reason: "screen update detected closed lid")
            BrightIntoshSettings.shared.brightintoshActive = false
            return
        }
        
        guard enabled else {
            return
        }
        
        if !newScreens.isEmpty {
            if BrightIntoshSettings.shared.brightintoshActive {
                if !brightnessTechnique.isEnabled {
                    scheduleReenableAfterDisplayStabilization(reason: "screen setup changed while technique disabled")
                } else if changedScreens {
                    brightnessTechnique.screenUpdate(screens: xdrScreens)
                } else {
                    brightnessTechnique.adjustBrightness()
                }
            }
        } else {
            print("Disabling compatibility brightness")
            aggressivelyResetCompatibilityBrightness(reason: "no screens")
        }
    }
    
    @MainActor
    private func enableExtraBrightness() {
        suppressAggressiveScreenParameterResetUntil = Date().addingTimeInterval(postEnableScreenParameterSuppression)
        brightnessTechnique.enable()
    }
    
    @MainActor
    private func aggressivelyResetCompatibilityBrightness(reason: String) {
        print("Aggressively resetting compatibility brightness: \(reason)")
        CGDisplayRestoreColorSyncSettings()
        brightnessTechnique.prepareForDisplayTopologyChange()
        CGDisplayRestoreColorSyncSettings()
    }
    
    @MainActor
    private func shouldDisableForClosedLid(currentScreens: [NSScreen]) -> Bool {
        guard BrightIntoshSettings.shared.disableWhenLidClosed else {
            return false
        }
        if let clamshellClosed = isClamshellClosed() {
            return clamshellClosed
        }
        return !currentScreens.isEmpty && !currentScreens.contains(where: { isBuiltInScreen(screen: $0) })
    }
    
    @MainActor
    func appendSupportDiagnostics(to report: inout String) {
        report += "Compatibility brightness manager:\n"
        report += " - Manager enabled: \(enabled)\n"
        report += " - Increased brightness setting: \(BrightIntoshSettings.shared.brightintoshActive)\n"
        brightnessTechnique.appendSupportDiagnostics(to: &report)
    }
}
