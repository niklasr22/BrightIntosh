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


class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var overlayAvailable: Bool = false
    
    let settingsWindowController = SettingsWindowController()
    
    var statusBarMenu: StatusBarMenu?
    var brightnessManager: BrightnessManager?
    var automationManager: AutomationManager?
    var supportedDevice: Bool = false
    
    
    private var trialTimer: Timer?
    
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
    }
    
    func isExtraBrightnessAllowed(offerUpgrade: Bool) async -> Bool {
#if STORE
        if await EntitlementHandler.shared.isUnrestrictedUser() {
            return true
        }
        do {
            let stillEntitledToTrial = (try await TrialData.getTrialData()).stillEntitled()
            if !stillEntitledToTrial && offerUpgrade {
                DispatchQueue.main.async {
                    self.settingsWindowController.showWindow(nil)
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
        Settings.shared.brightness = min(getDeviceMaxBrightness(), Settings.shared.brightness + 0.05)
    }
    
    @objc func decreaseBrightness() {
        Settings.shared.brightness = max(1.0, Settings.shared.brightness - 0.05)
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
    }
    
    @objc func toggleBrightIntosh() {
        if !Settings.shared.brightintoshActive && !checkBatteryAutomationContradiction() {
            return
        }
        
        Settings.shared.brightintoshActive.toggle()
    }
    
    func welcomeWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let controller = WelcomeWindowController(supportedDevice: supportedDevice)
        NSApp.runModal(for: controller.window!)
        UserDefaults.standard.set(true, forKey: "agreementAccepted")
    }
    
    func startTrialTimer() {
        if trialTimer != nil {
            return
        }
        // check every 5min
        trialTimer = Timer(timeInterval: 300, repeats: true, block: {t in self.revalidateTrial()})
        RunLoop.main.add(self.trialTimer!, forMode: RunLoop.Mode.common)
    }
    
    func revalidateTrial() {
        if !Settings.shared.brightintoshActive {
            stopTrialTimer()
            return
        }
        Task {
            if !(await self.isExtraBrightnessAllowed(offerUpgrade: true)) {
                // turn brightintosh off if user is not entitled
                DispatchQueue.main.async {
                    Settings.shared.brightintoshActive = false
                }
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

}
