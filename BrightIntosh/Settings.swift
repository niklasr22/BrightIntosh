//
//  Settings.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 23.09.23.
//

import Foundation
import ServiceManagement
#if !STORE
import Sparkle
#endif

final class Settings: NSObject {
    @objc static let shared = Settings()
    
    
    @objc dynamic public var brightintoshActive = UserDefaults.standard.object(forKey: "active") != nil ? UserDefaults.standard.bool(forKey: "active") : true {
        didSet {
            UserDefaults.standard.setValue(brightintoshActive, forKey: "active")
        }
    }
    
    @objc dynamic public var brightness: Float = UserDefaults.standard.object(forKey: "brightness") != nil ? UserDefaults.standard.float(forKey: "brightness") : 1.6 {
        didSet {
            UserDefaults.standard.setValue(brightness, forKey: "brightness")
        }
    }
    
    @objc dynamic public var overlayTechnique = UserDefaults.standard.object(forKey: "overlayTechnique") != nil ? UserDefaults.standard.bool(forKey: "overlayTechnique") : false {
        didSet {
            UserDefaults.standard.setValue(overlayTechnique, forKey: "overlayTechnique")
        }
    }
    
    @objc dynamic public var batteryAutomation = UserDefaults.standard.object(forKey: "batteryAutomation") != nil ? UserDefaults.standard.bool(forKey: "batteryAutomation") : false {
        didSet {
            UserDefaults.standard.setValue(batteryAutomation, forKey: "batteryAutomation")
        }
    }
    
    @objc dynamic public var batteryAutomationThreshold = UserDefaults.standard.object(forKey: "batteryAutomationThreshold") != nil ? UserDefaults.standard.integer(forKey: "batteryAutomationThreshold") : 50 {
        didSet {
            UserDefaults.standard.setValue(batteryAutomationThreshold, forKey: "batteryAutomationThreshold")
        }
    }
    
    public var launchAtLogin = false {
        didSet {
            if #available(macOS 13, *) {
                let service = SMAppService.mainApp
                do {
                    if launchAtLogin {
                        try service.register()
                    } else {
                        try service.unregister()
                    }
                } catch {
                    launchAtLogin.toggle()
                }
            } else {
                SMLoginItemSetEnabled(launcherBundleId, launchAtLogin)
                UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLoginActive")
            }
        }
    }
    
#if !STORE
    public let updaterController: SPUStandardUpdaterController
    
    public var autoUpdateCheck = UserDefaults.standard.object(forKey: "autoUpdateCheckActive") != nil ? UserDefaults.standard.bool(forKey: "autoUpdateCheckActive") : true {
        didSet {
            UserDefaults.standard.setValue(autoUpdateCheck, forKey: "autoUpdateCheckActive")
            updaterController.updater.automaticallyChecksForUpdates = autoUpdateCheck
        }
    }
#endif
    
    override init() {
        
#if !STORE
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        if UserDefaults.standard.object(forKey: "autoUpdateCheckActive") == nil {
            autoUpdateCheck = updaterController.updater.automaticallyChecksForUpdates
        }
#endif
        
        // Load launch at login status
        if #available(macOS 13, *) {
            launchAtLogin = SMAppService.mainApp.status == SMAppService.Status.enabled
        } else {
            launchAtLogin = UserDefaults.standard.object(forKey: "launchAtLoginActive") != nil && UserDefaults.standard.bool(forKey: "launchAtLoginActive")
        }
        super.init()
    }
}
