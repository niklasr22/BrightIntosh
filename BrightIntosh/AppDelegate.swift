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
    var automationManager: AutomationManager?
    
    override init() {
        settings = Settings.shared
        super.init()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        if UserDefaults.standard.object(forKey: "agreementAccepted") == nil || !UserDefaults.standard.bool(forKey: "agreementAccepted") {
            welcomeWindow()
        }
        
        brightnessManager = BrightnessManager()
        automationManager = AutomationManager()
        
        
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
        observationBrightness = observe(\.settings.brightness, options: [.old, .new]) {
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
        
        // centered brightness slider
        let brightnessSliderItem = NSMenuItem()
        
        let sliderContainerView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 35))
        let horizontalPadding: CGFloat = 5.0
        let sliderWidth = sliderContainerView.frame.width - (2 * horizontalPadding)
        let sliderHeight = 30.0
        let sliderX = (sliderContainerView.frame.width - sliderWidth) / 2
        let sliderY = (sliderContainerView.frame.height - sliderWidth) / 2
        
        let brightnessSlider = NSSlider(value: Double(Settings.shared.brightness), minValue: 1.0, maxValue: 1.6, target: self, action: #selector(brightnessSliderMoved))
        brightnessSlider.frame = NSRect(x: sliderX, y: sliderY, width: sliderWidth, height: sliderHeight)
        brightnessSlider.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        sliderContainerView.addSubview(brightnessSlider)
        sliderContainerView.autoresizingMask = [.width]
        brightnessSliderItem.view = sliderContainerView
        
        let toggleIncreasedBrightness = NSMenuItem(title: Settings.shared.brightintoshActive ? "Disable" : "Activate", action: #selector(toggleBrightIntosh), keyEquivalent: "")
        toggleIncreasedBrightness.setShortcut(for: .toggleBrightIntosh)
        
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "")
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(exitBrightIntosh), keyEquivalent: "")
        
        menu.addItem(titleItem)
        menu.addItem(toggleIncreasedBrightness)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Brightness:", action: nil, keyEquivalent: ""))
        menu.addItem(brightnessSliderItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(settingsItem)
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc func brightnessSliderMoved(slider: NSSlider) {
        Settings.shared.brightness = slider.floatValue
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
        if !Settings.shared.brightintoshActive && !checkBatteryAutomationContradiction() {
            return
        }
        
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

