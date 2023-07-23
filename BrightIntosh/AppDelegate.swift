//
//  AppDelegate.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 12.07.23.
//

import Cocoa
import SwiftUI
import ServiceManagement

struct SwiftUIView: View {
    var body: some View {
        Text("Hello, SwiftUI!")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    
    private var launchAtLogin = false
    private var active = UserDefaults.standard.object(forKey: "active") != nil ? UserDefaults.standard.bool(forKey: "active") : true {
        didSet {
            UserDefaults.standard.set(active, forKey: "active")
        }
    }
    
    private var overlayAvailable = false
    
    var overlayWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        if let builtInScreen = getBuiltInScreen(), active {
            setupOverlay(screen: builtInScreen)
        }
        
        // Observe displays
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParameters),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
        
        // Menu bar app
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        // Load launch at login status
        launchAtLogin = SMAppService.mainApp.status == SMAppService.Status.enabled
        
        setupMenus()
        
        if AXIsProcessTrusted() {
            addKeyListeners()
        }
    }
    
    func setupOverlay(screen: NSScreen) {
        let rect = NSRect(x: screen.visibleFrame.origin.x, y: screen.visibleFrame.origin.y, width: screen.frame.width, height: screen.frame.height)
        overlayWindow = OverlayWindow(rect: rect, screen: screen)
        overlayAvailable = true
    }
    
    func destroyOverlay() {
        if let overlayWindow {
            overlayWindow.close()
            overlayAvailable = false
        }
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
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: active ? "sun.max.circle.fill" : "sun.max.circle", accessibilityDescription: active ? "Increased brightness" : "Default brightness")
        }
        
        let menu = NSMenu()
        
        let title = NSMenuItem(title: "BrightIntosh", action: nil, keyEquivalent: "")
        let toggleOverlay = NSMenuItem(title: active ? "Disable" : "Activate", action: #selector(toggleBrightIntosh), keyEquivalent: "b")
        toggleOverlay.keyEquivalentModifierMask = [NSEvent.ModifierFlags.command, NSEvent.ModifierFlags.shift]
        let toggleLaunchAtLogin = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        if launchAtLogin {
            toggleLaunchAtLogin.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Launch at login active")
        }
        let exit = NSMenuItem(title: "Exit", action: #selector(exitBrightIntosh), keyEquivalent: "")
        menu.addItem(title)
        menu.addItem(toggleOverlay)
        menu.addItem(toggleLaunchAtLogin)
        menu.addItem(exit)
        
        if !AXIsProcessTrusted() {
            let requestAccessibilityFeaturesItem = NSMenuItem(title: "Enable global hot key", action: #selector(requestAccessibilityFeatures), keyEquivalent: "")
            menu.addItem(requestAccessibilityFeaturesItem)
        }
        
        statusItem.menu = menu
    }
    
    @objc func requestAccessibilityFeatures() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        AXIsProcessTrustedWithOptions(options)
        
        AccessibilityService.startPollingTrustedProcessState(getsTrusted: self.gotTrusted)
    }
    
    func gotTrusted() {
        setupMenus()
        addKeyListeners()
    }
    
    func addKeyListeners() {
        NSEvent.addGlobalMonitorForEvents(matching: NSEvent.EventTypeMask.keyDown, handler: {(event: NSEvent) -> Void in
            if let chars = event.characters, event.modifierFlags.contains(NSEvent.ModifierFlags.command) && event.modifierFlags.contains(NSEvent.ModifierFlags.shift) && chars.contains("b") {
                self.toggleBrightIntosh()
            }
        })
    }
    
    @objc func toggleBrightIntosh() {
        active.toggle()
        setupMenus()
        if active {
            if let builtInScreen = getBuiltInScreen() {
                setupOverlay(screen: builtInScreen)
            }
        } else {
            destroyOverlay()
        }
    }
    
    @objc func toggleLaunchAtLogin() {
        launchAtLogin.toggle()
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
        setupMenus()
    }
    
    @objc func handleScreenParameters() {
        if let builtInScreen = getBuiltInScreen() {
            if !overlayAvailable && active {
                setupOverlay(screen: builtInScreen)
            }
        } else {
            destroyOverlay()
        }
    }
    
    @objc func exitBrightIntosh() {
        exit(0)
    }
}

