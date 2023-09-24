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

extension NSScreen {
    var displayId: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    
    
    private var overlayAvailable = false
    
    private var overlayWindow: OverlayWindow?
    
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
    
    override init() {
        settings = Settings.shared
        super.init()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        
        if UserDefaults.standard.object(forKey: "agreementAccepted") == nil || !UserDefaults.standard.bool(forKey: "agreementAccepted") {
            welcomeWindow()
        }
        
        if let builtInScreen = getBuiltInScreen(), Settings.shared.brightintoshActive {
            setupOverlay(screen: builtInScreen)
        }
        
        // Observe displays
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParameters(notification:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
        
        // Menu bar app
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        setupMenus()
        
        // Register global hotkeys
        addKeyListeners()
        
        // Observe application state
        observationBrightIntoshActive = observe(\.settings.brightintoshActive, options: [.old, .new]) {
            object, change in
            print("Toggled increased brightness. Active: \(Settings.shared.brightintoshActive)")
            
            self.setupMenus()
            if Settings.shared.brightintoshActive {
                if let builtInScreen = self.getBuiltInScreen() {
                    self.setupOverlay(screen: builtInScreen)
                }
            } else {
                self.destroyOverlay()
                self.resetGammaTable()
            }
        }
        
        observationBrightness = observe(\.settings.brightness, options: [.old, .new]) {
            object, change in
            if let overlayWindow = self.overlayWindow {
                self.adjustGammaTable(screen: overlayWindow.getScreen()!)
                print("Set brightness to \(Settings.shared.brightness)")
            }
        }
        
    }
    
    func setupOverlay(screen: NSScreen) {
        let rect = NSRect(x: screen.visibleFrame.origin.x, y: screen.visibleFrame.origin.y, width: 1, height: 1)
        overlayWindow = OverlayWindow(rect: rect, screen: screen)
        overlayAvailable = true
        adjustGammaTable(screen: screen)
    }
    
    func destroyOverlay() {
        if let overlayWindow {
            overlayWindow.close()
            overlayAvailable = false
        }
    }
    
    func adjustGammaTable(screen: NSScreen) {
        if let displayId = screen.displayId, Settings.shared.brightintoshActive {
            resetGammaTable()
            
            let tableSize: Int = 256 // The size of the gamma table
            var redTable = [CGGammaValue](repeating: 0, count: tableSize)
            var greenTable = [CGGammaValue](repeating: 0, count: tableSize)
            var blueTable = [CGGammaValue](repeating: 0, count: tableSize)
            var sampleCount: UInt32 = 0
            let result = CGGetDisplayTransferByTable(displayId, UInt32(tableSize), &redTable, &greenTable, &blueTable, &sampleCount)
            
            guard result == CGError.success else {
                return
            }
            
            let gamma = Settings.shared.brightness
            
            for i in 0..<redTable.count {
                redTable[i] = redTable[i] * gamma
            }
            for i in 0..<greenTable.count {
                greenTable[i] = greenTable[i] * gamma
            }
            for i in 0..<blueTable.count {
                blueTable[i] = blueTable[i] * gamma
            }
            CGSetDisplayTransferByTable(displayId, UInt32(tableSize), &redTable, &greenTable, &blueTable)
        }
    }
    
    func resetGammaTable() {
        CGDisplayRestoreColorSyncSettings()
    }
    
    func getBuiltInScreen() -> NSScreen? {
        for screen in NSScreen.screens {
            let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            let displayId: CGDirectDisplayID = screenNumber as! CGDirectDisplayID
            if (CGDisplayIsBuiltin(displayId) != 0) {
                return screen
            }
        }
        return nil
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
    
    @objc func handleScreenParameters(notification: Notification) {
        if let builtInScreen = getBuiltInScreen() {
            if !overlayAvailable && Settings.shared.brightintoshActive {
                setupOverlay(screen: builtInScreen)
            } else {
                overlayWindow?.screenUpdate(screen: builtInScreen)
            }
        } else {
            destroyOverlay()
        }
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
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        KeyboardShortcuts.isEnabled = false
    }
    
    func menuDidClose(_ menu: NSMenu) {
        KeyboardShortcuts.isEnabled = true
    }
}

