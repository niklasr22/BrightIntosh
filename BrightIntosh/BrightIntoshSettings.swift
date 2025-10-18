//
//  Settings.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 23.09.23.
//

import Foundation
import ServiceManagement

@MainActor
class BrightIntoshSettings {
    static let shared: BrightIntoshSettings = BrightIntoshSettings()
    
    public var ignoreAppTransaction = false
    
    public static func getUserDefault<T>(key: String, defaultValue: T) -> T {
        if let value = UserDefaults(suiteName:"group.de.brightintosh.app")!.object(forKey: key) as? T {
            return value
        }
        return defaultValue
    }

    public var brightintoshActive: Bool = BrightIntoshSettings.getUserDefault(key: "active", defaultValue: true) {
        didSet {
            UserDefaults(suiteName:"group.de.brightintosh.app")!.setValue(brightintoshActive, forKey: "active")
            callListeners(setting: "brightintoshActive")
        }
    }
    
    public var brightIntoshOnlyOnBuiltIn: Bool = BrightIntoshSettings.getUserDefault(key: "brightIntoshOnlyOnBuiltIn", defaultValue: false) {
        didSet {
            UserDefaults(suiteName:"group.de.brightintosh.app")!.setValue(brightIntoshOnlyOnBuiltIn, forKey: "brightIntoshOnlyOnBuiltIn")
            callListeners(setting: "brightIntoshOnlyOnBuiltIn")
        }
    }
    
    public var hideMenuBarItem: Bool = BrightIntoshSettings.getUserDefault(key: "hideMenuBarItem", defaultValue: false) {
        didSet {
            UserDefaults(suiteName:"group.de.brightintosh.app")!.setValue(hideMenuBarItem, forKey: "hideMenuBarItem")
            callListeners(setting: "hideMenuBarItem")
        }
    }

    public var brightness: Float = BrightIntoshSettings.getUserDefault(key: "brightness", defaultValue: getDeviceMaxBrightness()) {
        didSet {
            UserDefaults(suiteName:"group.de.brightintosh.app")!.setValue(brightness, forKey: "brightness")
            callListeners(setting: "brightness")
        }
    }
    
    public var batteryAutomation: Bool = BrightIntoshSettings.getUserDefault(key: "batteryAutomation", defaultValue: false) {
        didSet {
            UserDefaults(suiteName:"group.de.brightintosh.app")!.setValue(batteryAutomation, forKey: "batteryAutomation")
            callListeners(setting: "batteryAutomation")
        }
    }
    
    public var batteryAutomationThreshold: Int = BrightIntoshSettings.getUserDefault(key: "batteryAutomationThreshold", defaultValue: 50) {
        didSet {
            UserDefaults(suiteName:"group.de.brightintosh.app")!.setValue(batteryAutomationThreshold, forKey: "batteryAutomationThreshold")
            callListeners(setting: "batteryAutomationThreshold")
        }
    }
    
    public var powerAdapterAutomation: Bool = BrightIntoshSettings.getUserDefault(key: "powerAdapterAutomation", defaultValue: false) {
        didSet {
            UserDefaults(suiteName:"group.de.brightintosh.app")!.setValue(powerAdapterAutomation, forKey: "powerAdapterAutomation")
            callListeners(setting: "powerAdapterAutomation")
        }
    }
    
    public var timerAutomation: Bool = BrightIntoshSettings.getUserDefault(key: "timerAutomation", defaultValue: false) {
        didSet {
            UserDefaults(suiteName:"group.de.brightintosh.app")!.setValue(timerAutomation, forKey: "timerAutomation")
            callListeners(setting: "timerAutomation")
        }
    }
    
    public var timerAutomationTimeout: Int = BrightIntoshSettings.getUserDefault(key: "timerAutomationTimeout", defaultValue: 180) {
        didSet {
            UserDefaults(suiteName:"group.de.brightintosh.app")!.setValue(timerAutomationTimeout, forKey: "timerAutomationTimeout")
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
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(defaultsChanged(notification:)),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
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
    
    @MainActor @objc
    private func defaultsChanged(notification: Notification) {
        print("Settings were updated externally")
        refreshState()
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
