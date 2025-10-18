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
import SwiftUI

@MainActor
class BrightIntoshAppDelegate: NSObject {
    
    private let settingsWindowController = SettingsWindowController()
    
    private var statusBarMenu: StatusBarMenu?
    private var brightnessManager: BrightnessManager?
    private var automationManager: AutomationManager?
    private var supportedDevice: Bool = false
    
    @objc func increaseBrightness() {
        Task { @MainActor in
            BrightIntoshSettings.shared.brightness = min(getDeviceMaxBrightness(), BrightIntoshSettings.shared.brightness + 0.05)
        }
    }
    
    @objc func decreaseBrightness() {
        Task { @MainActor in
            BrightIntoshSettings.shared.brightness = max(1.0, BrightIntoshSettings.shared.brightness - 0.05)
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
            if !BrightIntoshSettings.shared.brightintoshActive && !checkBatteryAutomationContradiction() {
                return
            }
            
            BrightIntoshSettings.shared.brightintoshActive.toggle()
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

extension BrightIntoshAppDelegate: NSApplicationDelegate {
    
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
            BrightIntoshSettings.shared.brightIntoshOnlyOnBuiltIn = false
        }
        
        brightnessManager = BrightnessManager()
        automationManager = AutomationManager()
        statusBarMenu = StatusBarMenu(supportedDevice: supportedDevice, automationManager: automationManager!, settingsWindowController: settingsWindowController, toggleBrightIntosh: toggleBrightIntosh)
        
        // Register global hotkeys
        addKeyListeners()
        
        BrightIntoshSettings.shared.addListener(setting: "brightintoshActive") {
            print("Active state changed")
            /* Show Settings Store Window, when user is not authorized */
            guard !Authorizer.shared.isAllowed() else { return }
            Task { @MainActor in
                self.showSettingsWindow()
            }
        }
        
        Task {
            addSettingsToIndex()
        }
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(alarm(notification:)),
            name: Notification.Name("de.brightintosh.intent.setActive"),
            object: nil
        )
        
        ProcessInfo.processInfo.disableSuddenTermination()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if BrightIntoshSettings.shared.hideMenuBarItem {
            self.showSettingsWindow()
        }
        return false
    }
    
    @MainActor @objc
    private func alarm(notification: Notification) {
        toggleBrightIntosh()
    }
    
}

@main
struct AppWithMenuBarExtra: App {
    @NSApplicationDelegateAdaptor private var appDelegate: BrightIntoshAppDelegate
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @Environment(\.openSettings) private var openSettings
    
    @ObservedObject var viewModel = BasicSettingsViewModel()

    var body: some Scene {
    }
}
