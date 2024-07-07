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
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        Task {
            if #available(macOS 13.0, *) {
                await checkEntitlements()
            } else {
                // Fallback on earlier versions
            }
        }
        
        supportedDevice = isDeviceSupported()
        
        if UserDefaults.standard.object(forKey: "agreementAccepted") == nil || !UserDefaults.standard.bool(forKey: "agreementAccepted") {
            welcomeWindow()
        }
        
        if !supportedDevice {
            Settings.shared.brightIntoshOnlyOnBuiltIn = false
        }
        
        brightnessManager = BrightnessManager()
        automationManager = AutomationManager()
        statusBarMenu = StatusBarMenu(supportedDevice: supportedDevice, automationManager: automationManager!, settingsWindowController: settingsWindowController, toggleBrightIntosh: toggleBrightIntosh)
        
        // Register global hotkeys
        addKeyListeners()
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
    @available(macOS 13.0, *)
    func checkEntitlements() async {
        do {
            // Get the appTransaction.
            let shared = try await AppTransaction.shared
            if case .verified(let appTransaction) = shared {
                // Hard-code the major version number in which the app's business model changed.
                let newBusinessModelMajorVersion = "2"


                // Get the major version number of the version the customer originally purchased.
                let versionComponents = appTransaction.originalAppVersion.split(separator: ".")
                let originalMajorVersion = versionComponents[0]
                print(originalMajorVersion)
                print(appTransaction.debugDescription)

                if originalMajorVersion < newBusinessModelMajorVersion {
                    print("glück gehabt")
                    // This customer purchased the app before the business model changed.
                    // Deliver content that they're entitled to based on their app purchase.
                }
                else {
                    // This customer purchased the app after the business model changed.
                    print("pech")
                }
            }
        }
        catch {
            // Handle errors.
            print("woopsie")
        }
    }
}

