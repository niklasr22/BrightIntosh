//
//  AppDelegate.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 12.07.23.
//

import Cocoa
import KeyboardShortcuts
import ServiceManagement
import StoreKit
import CoreSpotlight

@MainActor
class AppDelegate: NSObject {
    
    private let settingsWindowController = SettingsWindowController()
    
    private var statusBarMenu: StatusBarMenu?
    private var brightnessManager: BrightnessManager?
    private var automationManager: AutomationManager?
    private var supportedDevice: Bool = false

    private var trialTimer: Timer?
    
    func isExtraBrightnessAllowed(offerUpgrade: Bool) async -> Bool {
#if STORE
        if let isUnrestricted = try? await EntitlementHandler.shared.isUnrestrictedUser(), isUnrestricted {
            return true
        }
        do {
            let stillEntitledToTrial = (try await TrialData.getTrialData()).stillEntitled()
            if !stillEntitledToTrial && offerUpgrade {
                Task { @MainActor in
                    self.showSettingsWindow()
                }
            }
            startTrialTimer()
            return stillEntitledToTrial
        } catch {
            return false
        }
#else
        return true
#endif
    }
    
    @objc func increaseBrightness() {
        Task { @MainActor in
            Settings.shared.brightness = min(getDeviceMaxBrightness(), Settings.shared.brightness + 0.05)
        }
    }
    
    @objc func decreaseBrightness() {
        Task { @MainActor in
            Settings.shared.brightness = max(1.0, Settings.shared.brightness - 0.05)
        }
    }
    
    func addKeyListeners() {
        KeyboardShortcuts.onKeyUp(for: .toggleBrightIntosh) {
            self.toggleBrightIntosh()
        }
        KeyboardShortcuts.onKeyUp(for: .increaseBrightness) {
            self.increaseBrightness()
        }
        KeyboardShortcuts.onKeyUp(for: .decreaseBrightness) {
            self.decreaseBrightness()
        }
        KeyboardShortcuts.onKeyUp(for: .openSettings, action: {
            self.showSettingsWindow()
        })
    }
    
    @objc func toggleBrightIntosh() {
        Task { @MainActor in
            
            if !Settings.shared.brightintoshActive && !checkBatteryAutomationContradiction() {
                return
            }
            
            Settings.shared.brightintoshActive.toggle()
        }
    }
    
    func welcomeWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let controller = WelcomeWindowController(supportedDevice: supportedDevice)
        NSApp.runModal(for: controller.window!)
        UserDefaults.standard.set(true, forKey: "agreementAccepted")
    }
    
    func showSettingsWindow() {
        self.settingsWindowController.showWindow(nil)
    }
    
    func startTrialTimer() {
        if trialTimer != nil {
            return
        }
        // check every 5min
        trialTimer = Timer(timeInterval: 300, repeats: true, block: {t in
            Task { @MainActor in
                self.revalidateTrial()
            }
        })
        RunLoop.main.add(self.trialTimer!, forMode: RunLoop.Mode.common)
    }
    
    func revalidateTrial() {
        if !Settings.shared.brightintoshActive {
            stopTrialTimer()
            return
        }
        Task { @MainActor in
            if !(await self.isExtraBrightnessAllowed(offerUpgrade: true)) {
                // turn brightintosh off if user is not entitled
                Settings.shared.brightintoshActive = false
            } else {
                stopTrialTimer()
            }
        }
    }
    
    func stopTrialTimer() {
        if trialTimer == nil {
            return
        }
        self.trialTimer?.invalidate()
        self.trialTimer = nil
    }

    
    func addSettingsToIndex() {
        let attributeSet = CSSearchableItemAttributeSet(contentType: UTType.application)
        attributeSet.title = NSLocalizedString("BrightIntosh Settings", comment: "")
        attributeSet.contentDescription = "Open the settings of BrightIntosh"
        attributeSet.thumbnailData = URL(string: "https://brightintosh.de/brightintosh_sm.png")!.dataRepresentation
        attributeSet.alternateNames = ["BrightIntosh Settings", "BrightIntosh", "Settings", "brightness"]

        let item = CSSearchableItem(uniqueIdentifier: "de.brightintosh.app.settings", domainIdentifier: "de.brightintosh.app", attributeSet: attributeSet)
        
        Task {
            do {
                try await CSSearchableIndex.default().indexSearchableItems([item])
            } catch {
                print("Error indexing settings")
            }
        }
    }
}

extension AppDelegate: NSApplicationDelegate {
    
    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        if userActivity.activityType == CSSearchableItemActionType,
           let uniqueIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
            if uniqueIdentifier == "de.brightintosh.app.settings" {
                self.showSettingsWindow()
                return true
            }
        }
        return false
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        supportedDevice = isDeviceSupported()
        
        if UserDefaults.standard.object(forKey: "agreementAccepted") == nil || !UserDefaults.standard.bool(forKey: "agreementAccepted") {
            welcomeWindow()
        }
        
        if !supportedDevice {
            Settings.shared.brightIntoshOnlyOnBuiltIn = false
        }
        
        brightnessManager = BrightnessManager(isExtraBrightnessAllowed: isExtraBrightnessAllowed)
        automationManager = AutomationManager()
        statusBarMenu = StatusBarMenu(supportedDevice: supportedDevice, automationManager: automationManager!, settingsWindowController: settingsWindowController, toggleBrightIntosh: toggleBrightIntosh, isExtraBrightnessAllowed: isExtraBrightnessAllowed)
        
        // Register global hotkeys
        addKeyListeners()
        
        Settings.shared.addListener(setting: "brightintoshActive") {
            if !Settings.shared.brightintoshActive {
                self.stopTrialTimer()
            }
        }
        
        Task {
            await isExtraBrightnessAllowed(offerUpgrade: true)
        }
        
        Task {
            addSettingsToIndex()
        }
    }
}
