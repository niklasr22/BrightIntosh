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

final class Settings {
    static let shared = Settings()
    
    
    public var brightintoshActive = UserDefaults.standard.object(forKey: "active") != nil ? UserDefaults.standard.bool(forKey: "active") : true {
        didSet {
            UserDefaults.standard.setValue(brightintoshActive, forKey: "active")
            callListeners(setting: "brightintoshActive")
        }
    }
    
    public var brightness: Float = UserDefaults.standard.object(forKey: "brightness") != nil ? UserDefaults.standard.float(forKey: "brightness") : 1.6 {
        didSet {
            UserDefaults.standard.setValue(brightness, forKey: "brightness")
            callListeners(setting: "brightness")
        }
    }
    
    public var overlayTechnique = UserDefaults.standard.object(forKey: "overlayTechnique") != nil ? UserDefaults.standard.bool(forKey: "overlayTechnique") : false {
        didSet {
            UserDefaults.standard.setValue(overlayTechnique, forKey: "overlayTechnique")
            callListeners(setting: "overlayTechnique")
        }
    }
    
    public var batteryAutomation = UserDefaults.standard.object(forKey: "batteryAutomation") != nil ? UserDefaults.standard.bool(forKey: "batteryAutomation") : false {
        didSet {
            UserDefaults.standard.setValue(batteryAutomation, forKey: "batteryAutomation")
            callListeners(setting: "batteryAutomation")
        }
    }
    
    public var batteryAutomationThreshold = UserDefaults.standard.object(forKey: "batteryAutomationThreshold") != nil ? UserDefaults.standard.integer(forKey: "batteryAutomationThreshold") : 50 {
        didSet {
            UserDefaults.standard.setValue(batteryAutomationThreshold, forKey: "batteryAutomationThreshold")
            callListeners(setting: "batteryAutomationThreshold")
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
            callListeners(setting: "launchAtLogin")
        }
    }
    
#if !STORE
    public let updaterController: SPUStandardUpdaterController
    
    public var autoUpdateCheck = UserDefaults.standard.object(forKey: "autoUpdateCheckActive") != nil ? UserDefaults.standard.bool(forKey: "autoUpdateCheckActive") : true {
        didSet {
            UserDefaults.standard.setValue(autoUpdateCheck, forKey: "autoUpdateCheckActive")
            updaterController.updater.automaticallyChecksForUpdates = autoUpdateCheck
            callListeners(setting: "autoUpdateCheckActive")
        }
    }
#endif
    
    private var listeners: [String: [()->()]] = [:]
    
    init() {
        
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
    }
    
    public func addListener(setting: String, callback: @escaping () ->()) {
        if !listeners.keys.contains(setting) {
            listeners[setting] = []
        }
        listeners[setting]?.append(callback)
    }
    
    private func callListeners(setting: String) {
        if let setting_listeners = listeners[setting] {
            setting_listeners.forEach { callback in
                callback()
            }
        }
    }
}
