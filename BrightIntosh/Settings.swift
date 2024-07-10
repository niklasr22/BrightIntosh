//
//  Settings.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 23.09.23.
//

import Foundation
import ServiceManagement


final class Settings {
    static let shared: Settings = Settings()
    
    
    public var entitledToUnrestrictedUse: Bool = UserDefaults.standard.object(forKey: "entitledToUnrestrictedUse") != nil ? UserDefaults.standard.bool(forKey: "entitledToUnrestrictedUse") : true {
        didSet {
            UserDefaults.standard.setValue(entitledToUnrestrictedUse, forKey: "entitledToUnrestrictedUse")
            callListeners(setting: "entitledToUnrestrictedUse")
        }
    }
    
    public var brightintoshActive: Bool = UserDefaults.standard.object(forKey: "active") != nil ? UserDefaults.standard.bool(forKey: "active") : true {
        didSet {
            UserDefaults.standard.setValue(brightintoshActive, forKey: "active")
            callListeners(setting: "brightintoshActive")
        }
    }
    
    public var brightIntoshOnlyOnBuiltIn: Bool = UserDefaults.standard.object(forKey: "brightIntoshOnlyOnBuiltIn") != nil ? UserDefaults.standard.bool(forKey: "brightIntoshOnlyOnBuiltIn") : false {
        didSet {
            UserDefaults.standard.setValue(brightintoshActive, forKey: "brightIntoshOnlyOnBuiltIn")
            callListeners(setting: "brightIntoshOnlyOnBuiltIn")
        }
    }

    public var brightness: Float = UserDefaults.standard.object(forKey: "brightness") != nil ? UserDefaults.standard.float(forKey: "brightness") : getDeviceMaxBrightness() {
        didSet {
            UserDefaults.standard.setValue(brightness, forKey: "brightness")
            callListeners(setting: "brightness")
        }
    }
    
    public var batteryAutomation: Bool = UserDefaults.standard.object(forKey: "batteryAutomation") != nil ? UserDefaults.standard.bool(forKey: "batteryAutomation") : false {
        didSet {
            UserDefaults.standard.setValue(batteryAutomation, forKey: "batteryAutomation")
            callListeners(setting: "batteryAutomation")
        }
    }
    
    public var batteryAutomationThreshold: Int = UserDefaults.standard.object(forKey: "batteryAutomationThreshold") != nil ? UserDefaults.standard.integer(forKey: "batteryAutomationThreshold") : 50 {
        didSet {
            UserDefaults.standard.setValue(batteryAutomationThreshold, forKey: "batteryAutomationThreshold")
            callListeners(setting: "batteryAutomationThreshold")
        }
    }
    
    public var timerAutomation: Bool = UserDefaults.standard.object(forKey: "timerAutomation") != nil ? UserDefaults.standard.bool(forKey: "timerAutomation") : false {
        didSet {
            UserDefaults.standard.setValue(timerAutomation, forKey: "timerAutomation")
            callListeners(setting: "timerAutomation")
        }
    }
    
    public var timerAutomationTimeout: Int = UserDefaults.standard.object(forKey: "timerAutomationTimeout") != nil ? UserDefaults.standard.integer(forKey: "timerAutomationTimeout") : 180 {
        didSet {
            UserDefaults.standard.setValue(timerAutomationTimeout, forKey: "timerAutomationTimeout")
            callListeners(setting: "timerAutomationTimeout")
        }
    }
    
    public var launchAtLogin: Bool = false {
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
    
    private var listeners: [String: [()->()]] = [:]
    
    init() {
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
