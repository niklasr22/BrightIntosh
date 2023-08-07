//
//  AppDelegate.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 12.07.23.
//

import Cocoa
import ServiceManagement
import Carbon

extension NSScreen {
    var displayId: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    
    private var launchAtLogin = false
    private var active = UserDefaults.standard.object(forKey: "active") != nil ? UserDefaults.standard.bool(forKey: "active") : true {
        didSet {
        }
    }
    
    private var overlayAvailable = false
    
    private var overlayWindow: OverlayWindow?
    
    private var appVersion: String?
    
    private var newVersionAvailable = false
    
    private let BRIGHTINTOSH_URL = "https://brightintosh.de"
    private let BRIGHTINTOSH_VERSION_URL = "https://api.github.com/repos/niklasr22/BrightIntosh/releases/latest"
    
    private var gamma: Float = 1.7
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        
        #if !STORE
        if UserDefaults.standard.object(forKey: "agreementAccepted") == nil || !UserDefaults.standard.bool(forKey: "agreementAccepted") {
            firstStartWarning()
        }
        #endif
        
        if let builtInScreen = getBuiltInScreen(), active {
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
        
        // Load launch at login status
        launchAtLogin = SMAppService.mainApp.status == SMAppService.Status.enabled
        
        setupMenus()
        
        // Register global hotkey
        addKeyListeners()
        /* TODO: Use this once Carbon is fully deprecated without a better successor.
         if AXIsProcessTrusted() {
            addKeyListeners()
        }*/
        
        #if !STORE
        // Schedule version check every 3 hours
        let versionCheckDate = Date()
        let versionCheckTimer = Timer(fire: versionCheckDate, interval: 10800, repeats: true, block: {t in self.fetchNewestVersion()})
        RunLoop.main.add(versionCheckTimer, forMode: RunLoop.Mode.default)
        #endif
    }
    
    func firstStartWarning() {
        let alert = NSAlert()
        alert.messageText = "Use this application at your own risk. This software comes with no warranty or guarantees. Users take full responsibility for any problems that arise from the use of this software. By continuing and using the BrightIntosh application you accept the previous statement."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        let result = alert.runModal()
        if result == NSApplication.ModalResponse.alertSecondButtonReturn {
            NSApplication.shared.terminate(nil)
            return
        }
        UserDefaults.standard.set(true, forKey: "agreementAccepted")
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
        if let displayId = screen.displayId {
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
            
            for i in 0..<redTable.count {
                redTable[i] = redTable[i] * gamma
            }
            for i in 0..<greenTable.count {
                greenTable[i] = greenTable[i] * gamma
            }
            for i in 0..<redTable.count {
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
        let titleString = "BrightIntosh SE (v\(appVersion ?? "?"))"
        #else
        let titleString = "BrightIntosh (v\(appVersion ?? "?"))"
        #endif
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: active ? "sun.max.circle.fill" : "sun.max.circle", accessibilityDescription: active ? "Increased brightness" : "Default brightness")
            button.toolTip = titleString
        }
        
        
        let title = NSMenuItem(title: titleString, action: #selector(openWebsite), keyEquivalent: "")
        let toggleOverlay = NSMenuItem(title: active ? "Disable" : "Activate", action: #selector(toggleBrightIntosh), keyEquivalent: "b")
        toggleOverlay.keyEquivalentModifierMask = [NSEvent.ModifierFlags.command, NSEvent.ModifierFlags.option]
        let toggleLaunchAtLogin = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        if launchAtLogin {
            toggleLaunchAtLogin.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Launch at login active")
        }
        let exit = NSMenuItem(title: "Exit", action: #selector(exitBrightIntosh), keyEquivalent: "")
        
        menu.addItem(title)
        menu.addItem(toggleOverlay)
        menu.addItem(toggleLaunchAtLogin)
        menu.addItem(exit)
        
        #if DEBUG
        let increaseGammaMenu = NSMenuItem(title: "Increase gamma", action: #selector(increaseGamma), keyEquivalent: "-")
        menu.addItem(increaseGammaMenu)
        let decreaseGammaMenu = NSMenuItem(title: "Decrease gamma", action: #selector(decreaseGamma), keyEquivalent: "+")
        menu.addItem(decreaseGammaMenu)
        increaseGammaMenu.keyEquivalentModifierMask = [NSEvent.ModifierFlags.command, NSEvent.ModifierFlags.option]
        decreaseGammaMenu.keyEquivalentModifierMask = [NSEvent.ModifierFlags.command, NSEvent.ModifierFlags.option]
        #endif
        
        /* TODO: Use this once Carbon is fully deprecated without a better successor.
        if !AXIsProcessTrusted() {
            let requestAccessibilityFeaturesItem = NSMenuItem(title: "Enable global hot key", action: #selector(requestAccessibilityFeatures), keyEquivalent: "")
            menu.addItem(requestAccessibilityFeaturesItem)
        }*/
        
        if newVersionAvailable {
            let newVersionItem = NSMenuItem(title: "Download a new version", action: #selector(openWebsite), keyEquivalent: "")
            newVersionItem.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Download a new version")
            menu.addItem(newVersionItem)
        }
        
        statusItem.menu = menu
    }
    
    @objc func increaseGamma() {
        gamma += 0.05
        adjustGammaTable(screen: overlayWindow!.screen!)
    }
    
    @objc func decreaseGamma() {
        gamma -= 0.05
        adjustGammaTable(screen: overlayWindow!.screen!)
    }
    
    /* TODO: Use this once Carbon is fully deprecated without a better successor.
     @objc func requestAccessibilityFeatures() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        AXIsProcessTrustedWithOptions(options)
        
        AccessibilityService.startPollingTrustedProcessState(getsTrusted: self.gotTrusted)
    }*/
    
    func gotTrusted() {
        setupMenus()
        addKeyListeners()
    }
    
    func addKeyListeners() {
        /* TODO: Use this once Carbon is fully deprecated without a better successor.
         NSEvent.addGlobalMonitorForEvents(matching: NSEvent.EventTypeMask.keyDown, handler: {(event: NSEvent) -> Void in
            if let chars = event.characters, event.modifierFlags.contains(NSEvent.ModifierFlags.command) && event.modifierFlags.contains(NSEvent.ModifierFlags.shift) && chars.contains("b") {
                self.toggleBrightIntosh()
            }
        })*/
        
        HotKeyUtils.registerHotKey(modifierFlags: UInt32(0 | optionKey | cmdKey) , keyCode: UInt32(kVK_ANSI_B), callback: self.toggleBrightIntosh)
        HotKeyUtils.registerHotKey(modifierFlags: UInt32(1 | optionKey | cmdKey) , keyCode: UInt32(kVK_ANSI_Minus), callback: self.decreaseGamma)
        HotKeyUtils.registerHotKey(modifierFlags: UInt32(2 | optionKey | cmdKey) , keyCode: UInt32(kVK_ANSI_Equal), callback: self.increaseGamma)
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
            resetGammaTable()
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
    
    @objc func handleScreenParameters(notification: Notification) {
        if let builtInScreen = getBuiltInScreen() {
            if !overlayAvailable && active {
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
    
    #if !STORE
    @objc func fetchNewestVersion() {
        let url = URL(string: BRIGHTINTOSH_VERSION_URL)!
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data else {
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
                let version = json["tag_name"] as! String
                if version != "v" + (self.appVersion ?? "") {
                    self.newVersionAvailable = true
                    DispatchQueue.main.async {
                        self.setupMenus()
                    }
                }
            } catch {}
        }
        task.resume()
    }
    #endif
    
    @objc func openWebsite() {
        NSWorkspace.shared.open(URL(string: BRIGHTINTOSH_URL)!)
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        HotKeyUtils.unregisterAllHotKeys()
    }
    
    func menuDidClose(_ menu: NSMenu) {
        addKeyListeners()
    }
}

