//
//  AppDelegate.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 12.07.23.
//

import Cocoa
import KeyboardShortcuts
import ServiceManagement
import Carbon
import SwiftUI


class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    
    
    private var overlayAvailable = false
    
    
#if !STORE
    private let BRIGHTINTOSH_URL = "https://brightintosh.de"
#else
    private let BRIGHTINTOSH_URL = "https://brightintosh.de/index_nd.html"
#endif
    
    private let BRIGHTINTOSH_VERSION_URL = "https://api.github.com/repos/niklasr22/BrightIntosh/releases/latest"
    
    
    let settingsWindowController = SettingsWindowController()
    
    
    @objc var settings: Settings
    
    var observationBrightIntoshActive: NSKeyValueObservation?
    var observationBrightness: NSKeyValueObservation?
    
    var brightnessManager: BrightnessManager?
    
    override init() {
        settings = Settings.shared
        super.init()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        if UserDefaults.standard.object(forKey: "agreementAccepted") == nil || !UserDefaults.standard.bool(forKey: "agreementAccepted") {
            welcomeWindow()
        }
        
        brightnessManager = BrightnessManager()
        
        // Menu bar app
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        setupMenus()
        
        // Register global hotkeys
        addKeyListeners()
        
        // Observe application state
        observationBrightIntoshActive = observe(\.settings.brightintoshActive, options: [.old, .new]) {
            object, change in
            self.setupMenus()
        }
    }
    
    func setupMenus() {
        
        let menu = NSMenu()
        menu.delegate = self
        
#if STORE
        let titleString = "BrightIntosh SE (v\(appVersion))"
#else
        let titleString = "BrightIntosh (v\(appVersion))"
#endif
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: Settings.shared.brightintoshActive ? "sun.max.circle.fill" : "sun.max.circle", accessibilityDescription: Settings.shared.brightintoshActive ? "Increased brightness" : "Default brightness")
            button.toolTip = titleString
        }
        
        
        let titleItem = NSMenuItem(title: titleString, action: #selector(openWebsite), keyEquivalent: "")

        let toggleIncreasedBrightness = NSMenuItem(title: Settings.shared.brightintoshActive ? "Disable" : "Activate", action: #selector(toggleBrightIntosh), keyEquivalent: "")
        toggleIncreasedBrightness.setShortcut(for: .toggleBrightIntosh)
        
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "")
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(exitBrightIntosh), keyEquivalent: "")
        
        menu.addItem(titleItem)
        menu.addItem(toggleIncreasedBrightness)
        menu.addItem(settingsItem)
        menu.addItem(quitItem)
        
#if DEBUG
        let increaseItem = NSMenuItem(title: "Increase gamma", action: #selector(increaseBrightness), keyEquivalent: "")
        increaseItem.setShortcut(for: .increaseBrightness)
        menu.addItem(increaseItem)
        let decreaseItem = NSMenuItem(title: "Decrease gamma", action: #selector(decreaseBrightness), keyEquivalent: "")
        decreaseItem.setShortcut(for: .decreaseBrightness)
        menu.addItem(decreaseItem)
#endif
        
        statusItem.menu = menu
    }
    
    @objc func increaseBrightness() {
        Settings.shared.brightness = min(1.6, Settings.shared.brightness + 0.05)
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
        Settings.shared.brightintoshActive.toggle()
    }
    
    @objc func exitBrightIntosh() {
        exit(0)
    }
    
    @objc func openWebsite() {
        NSWorkspace.shared.open(URL(string: BRIGHTINTOSH_URL)!)
    }
    
    @objc func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApp.runModal(for: settingsWindowController.window!)
    }
    
    func welcomeWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let controller = WelcomeWindowController()
        NSApp.runModal(for: controller.window!)
        UserDefaults.standard.set(true, forKey: "agreementAccepted")
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        KeyboardShortcuts.isEnabled = false
    }
    
    func menuDidClose(_ menu: NSMenu) {
        KeyboardShortcuts.isEnabled = true
    }
}

