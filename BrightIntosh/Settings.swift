//
//  Settings.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 23.09.23.
//

import Foundation
import ServiceManagement

@MainActor
class Settings {
    static let shared: Settings = Settings()
    
    public var ignoreAppTransaction = false
    
    public static func getUserDefault<T>(key: String, defaultValue: T) -> T {
        if let value = UserDefaults.standard.object(forKey: key) as? T {
            return value
        }
        return defaultValue
    }

    public var brightintoshActive: Bool = Settings.getUserDefault(key: "active", defaultValue: true) {
        didSet {
            UserDefaults.standard.setValue(brightintoshActive, forKey: "active")
            callListeners(setting: "brightintoshActive")
        }
    }
    
    public var brightIntoshOnlyOnBuiltIn: Bool = Settings.getUserDefault(key: "brightIntoshOnlyOnBuiltIn", defaultValue: false) {
        didSet {
            UserDefaults.standard.setValue(brightIntoshOnlyOnBuiltIn, forKey: "brightIntoshOnlyOnBuiltIn")
            callListeners(setting: "brightIntoshOnlyOnBuiltIn")
        }
    }
    
    public var hideMenuBarItem: Bool = Settings.getUserDefault(key: "hideMenuBarItem", defaultValue: false) {
        didSet {
            UserDefaults.standard.setValue(hideMenuBarItem, forKey: "hideMenuBarItem")
            callListeners(setting: "hideMenuBarItem")
        }
    }

    public var brightness: Float = Settings.getUserDefault(key: "brightness", defaultValue: getDeviceMaxBrightness()) {
        didSet {
            UserDefaults.standard.setValue(brightness, forKey: "brightness")
            callListeners(setting: "brightness")
        }
    }
    
    public var batteryAutomation: Bool = Settings.getUserDefault(key: "batteryAutomation", defaultValue: false) {
        didSet {
            UserDefaults.standard.setValue(batteryAutomation, forKey: "batteryAutomation")
            callListeners(setting: "batteryAutomation")
        }
    }
    
    public var batteryAutomationThreshold: Int = Settings.getUserDefault(key: "batteryAutomationThreshold", defaultValue: 50) {
        didSet {
            UserDefaults.standard.setValue(batteryAutomationThreshold, forKey: "batteryAutomationThreshold")
            callListeners(setting: "batteryAutomationThreshold")
        }
    }
    
    public var powerAdapterAutomation: Bool = Settings.getUserDefault(key: "powerAdapterAutomation", defaultValue: false) {
        didSet {
            UserDefaults.standard.setValue(powerAdapterAutomation, forKey: "powerAdapterAutomation")
            callListeners(setting: "powerAdapterAutomation")
        }
    }
    
    public var timerAutomation: Bool = Settings.getUserDefault(key: "timerAutomation", defaultValue: false) {
        didSet {
            UserDefaults.standard.setValue(timerAutomation, forKey: "timerAutomation")
            callListeners(setting: "timerAutomation")
        }
    }
    
    public var timerAutomationTimeout: Int = Settings.getUserDefault(key: "timerAutomationTimeout", defaultValue: 180) {
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
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(defaultsChanged(notification:)),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }
    
    private func refreshState() {
        brightintoshActive = Settings.getUserDefault(key: "active", defaultValue: true)
        brightIntoshOnlyOnBuiltIn = Settings.getUserDefault(key: "brightIntoshOnlyOnBuiltIn", defaultValue: false)
        hideMenuBarItem = Settings.getUserDefault(key: "hideMenuBarItem", defaultValue: false)
        brightness = Settings.getUserDefault(key: "brightness", defaultValue: getDeviceMaxBrightness())
        batteryAutomation = Settings.getUserDefault(key: "batteryAutomation", defaultValue: false)
        batteryAutomationThreshold = Settings.getUserDefault(key: "batteryAutomationThreshold", defaultValue: 50)
        powerAdapterAutomation = Settings.getUserDefault(key: "powerAdapterAutomation", defaultValue: false)
        timerAutomation = Settings.getUserDefault(key: "timerAutomation", defaultValue: false)
        timerAutomationTimeout = Settings.getUserDefault(key: "timerAutomationTimeout", defaultValue: 180)
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
