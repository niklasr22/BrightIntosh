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
    
    public var ignoreAppTransaction = false
    
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
    
    public var hideMenuBarItem: Bool = UserDefaults.standard.object(forKey: "hideMenuBarItem") != nil ? UserDefaults.standard.bool(forKey: "hideMenuBarItem") : false {
        didSet {
            UserDefaults.standard.setValue(hideMenuBarItem, forKey: "hideMenuBarItem")
            callListeners(setting: "hideMenuBarItem")
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
            callListeners(setting: "launchAtLogin")
        }
    }
    
    private var listeners: [String: [()->()]] = [:]
    
    init() {
        // Load launch at login status
        launchAtLogin = SMAppService.mainApp.status == SMAppService.Status.enabled
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
