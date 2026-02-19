//
//  Settings.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 23.09.23.
//

import Foundation
import ServiceManagement

extension UserDefaults {
    @objc dynamic var active: Bool {
        return bool(forKey: "active")
    }
    
    @objc dynamic var cliBrightness: Float {
        return float(forKey: "cliBrightness")
    }
}

@MainActor
class BrightIntoshSettings {
    static let shared: BrightIntoshSettings = BrightIntoshSettings()
    
    public var ignoreAppTransaction = false
    
    public static let defaults = UserDefaults(suiteName: defaultsSuiteName)!
    
    public static func getUserDefault<T>(key: String, defaultValue: T) -> T {
        if let value = defaults.object(forKey: key) as? T {
            return value
        }
        return defaultValue
    }

    public var brightintoshActive: Bool = BrightIntoshSettings.getUserDefault(key: "active", defaultValue: true) {
        didSet {
            BrightIntoshSettings.defaults.setValue(brightintoshActive, forKey: "active")
            callListeners(setting: "brightintoshActive")
        }
    }
    
    public var brightIntoshOnlyOnBuiltIn: Bool = BrightIntoshSettings.getUserDefault(key: "brightIntoshOnlyOnBuiltIn", defaultValue: false) {
        didSet {
            BrightIntoshSettings.defaults.setValue(brightIntoshOnlyOnBuiltIn, forKey: "brightIntoshOnlyOnBuiltIn")
            callListeners(setting: "brightIntoshOnlyOnBuiltIn")
        }
    }
    
    public var hideMenuBarItem: Bool = BrightIntoshSettings.getUserDefault(key: "hideMenuBarItem", defaultValue: false) {
        didSet {
            BrightIntoshSettings.defaults.setValue(hideMenuBarItem, forKey: "hideMenuBarItem")
            callListeners(setting: "hideMenuBarItem")
        }
    }

    public var brightness: Float = BrightIntoshSettings.getUserDefault(key: "brightness", defaultValue: getDeviceMaxBrightness()) {
        didSet {
            BrightIntoshSettings.defaults.setValue(brightness, forKey: "brightness")
            callListeners(setting: "brightness")
        }
    }
    
    public var cliBrightness: Float = BrightIntoshSettings.getUserDefault(key: "cliBrightness", defaultValue: getDeviceMaxBrightness()) {
        didSet {
            BrightIntoshSettings.defaults.setValue(cliBrightness, forKey: "cliBrightness")
            callListeners(setting: "cliBrightness")
        }
    }
    
    
    public var batteryAutomation: Bool = BrightIntoshSettings.getUserDefault(key: "batteryAutomation", defaultValue: false) {
        didSet {
            BrightIntoshSettings.defaults.setValue(batteryAutomation, forKey: "batteryAutomation")
            callListeners(setting: "batteryAutomation")
        }
    }
    
    public var batteryAutomationThreshold: Int = BrightIntoshSettings.getUserDefault(key: "batteryAutomationThreshold", defaultValue: 50) {
        didSet {
            BrightIntoshSettings.defaults.setValue(batteryAutomationThreshold, forKey: "batteryAutomationThreshold")
            callListeners(setting: "batteryAutomationThreshold")
        }
    }
    
    public var powerAdapterAutomation: Bool = BrightIntoshSettings.getUserDefault(key: "powerAdapterAutomation", defaultValue: false) {
        didSet {
            BrightIntoshSettings.defaults.setValue(powerAdapterAutomation, forKey: "powerAdapterAutomation")
            callListeners(setting: "powerAdapterAutomation")
        }
    }
    
    public var timerAutomation: Bool = BrightIntoshSettings.getUserDefault(key: "timerAutomation", defaultValue: false) {
        didSet {
            BrightIntoshSettings.defaults.setValue(timerAutomation, forKey: "timerAutomation")
            callListeners(setting: "timerAutomation")
        }
    }
    
    public var timerAutomationTimeout: Int = BrightIntoshSettings.getUserDefault(key: "timerAutomationTimeout", defaultValue: 180) {
        didSet {
            BrightIntoshSettings.defaults.setValue(timerAutomationTimeout, forKey: "timerAutomationTimeout")
            callListeners(setting: "timerAutomationTimeout")
        }
    }
    
    public var showInDock: Bool = BrightIntoshSettings.getUserDefault(key: "showInDock", defaultValue: false) {
        didSet {
            BrightIntoshSettings.defaults.setValue(showInDock, forKey: "showInDock")
            callListeners(setting: "showInDock")
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
    
    var activeObserver: NSKeyValueObservation?
    var cliBrightnessObserver: NSKeyValueObservation?

    init() {
        // Load launch at login status
        launchAtLogin = SMAppService.mainApp.status == SMAppService.Status.enabled
        migrateUserDefaultsToAppGroups();
        
        activeObserver = BrightIntoshSettings.defaults.observe(\.active, options: [.initial, .new], changeHandler: { (defaults, change) in
            Task { @MainActor in
                if let newValue = change.newValue, newValue != self.brightintoshActive {
                    self.brightintoshActive = newValue;
                }
            }
        })
        cliBrightnessObserver = BrightIntoshSettings.defaults.observe(\.cliBrightness, options: [.initial, .new], changeHandler: { (defaults, change) in
            Task { @MainActor in
                if let newValue = change.newValue, self.brightness != newValue {
                    self.brightness = newValue;
                }
            }
        })
    }
    
    private func refreshState() {
        brightintoshActive = BrightIntoshSettings.getUserDefault(key: "active", defaultValue: true)
        brightIntoshOnlyOnBuiltIn = BrightIntoshSettings.getUserDefault(key: "brightIntoshOnlyOnBuiltIn", defaultValue: false)
        hideMenuBarItem = BrightIntoshSettings.getUserDefault(key: "hideMenuBarItem", defaultValue: false)
        brightness = BrightIntoshSettings.getUserDefault(key: "brightness", defaultValue: getDeviceMaxBrightness())
        batteryAutomation = BrightIntoshSettings.getUserDefault(key: "batteryAutomation", defaultValue: false)
        batteryAutomationThreshold = BrightIntoshSettings.getUserDefault(key: "batteryAutomationThreshold", defaultValue: 50)
        powerAdapterAutomation = BrightIntoshSettings.getUserDefault(key: "powerAdapterAutomation", defaultValue: false)
        timerAutomation = BrightIntoshSettings.getUserDefault(key: "timerAutomation", defaultValue: false)
        timerAutomationTimeout = BrightIntoshSettings.getUserDefault(key: "timerAutomationTimeout", defaultValue: 180)
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
    
    private func migrateUserDefaultsToAppGroups() {
        let userDefaults = UserDefaults.standard
        let didMigrateToAppGroups = "didMigrateToAppGroups"
        
        if !BrightIntoshSettings.defaults.bool(forKey: didMigrateToAppGroups) {
            for key in userDefaults.dictionaryRepresentation().keys {
                BrightIntoshSettings.defaults.set(userDefaults.dictionaryRepresentation()[key], forKey: key)
            }
            BrightIntoshSettings.defaults.set(true, forKey: didMigrateToAppGroups)
            refreshState();
            print("Successfully migrated defaults")
        }
    }
}
