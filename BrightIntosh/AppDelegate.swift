//
//  AppDelegate.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 12.07.23.
//

import Cocoa
import SwiftUI
import ServiceManagement
import Carbon

struct SwiftUIView: View {
    var body: some View {
        Text("Hello, SwiftUI!")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension String {
  /// This converts string to UInt as a fourCharCode
  public var fourCharCodeValue: Int {
    var result: Int = 0
    if let data = self.data(using: String.Encoding.macOSRoman) {
      data.withUnsafeBytes({ (rawBytes) in
        let bytes = rawBytes.bindMemory(to: UInt8.self)
        for i in 0 ..< data.count {
          result = result << 8 + Int(bytes[i])
        }
      })
    }
    return result
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
    
    private var overlayWindow: NSWindow?
    
    private var appVersion: String?
    
    private var newVersionAvailable = false

    private let BRIGHTINTOSH_URL = "https://brightintosh.de"
    private let BRIGHTINTOSH_VERSION_URL = "https://api.github.com/repos/niklasr22/BrightIntosh/releases/latest"
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        
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
        
        if AXIsProcessTrusted() {
            addKeyListeners()
        }
        
        // Schedule version check every 3 hours
        let versionCheckDate = Date()
        let versionCheckTimer = Timer(fire: versionCheckDate, interval: 10800, repeats: true, block: {t in self.fetchNewestVersion()})
        RunLoop.main.add(versionCheckTimer, forMode: RunLoop.Mode.default)
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
        
        let title = NSMenuItem(title: "BrightIntosh (v\(appVersion ?? "?"))", action: #selector(openWebsite), keyEquivalent: "")
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
        
        if newVersionAvailable {
            let newVersionItem = NSMenuItem(title: "Download a new version", action: #selector(openWebsite), keyEquivalent: "")
            newVersionItem.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Download a new version")
            menu.addItem(newVersionItem)
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
    
    static func register() {
        var hotKeyRef: EventHotKeyRef?
        let modifierFlags: UInt32 =
          getCarbonFlagsFromCocoaFlags(cocoaFlags: NSEvent.ModifierFlags.command)

        let keyCode = kVK_ANSI_R
        var gMyHotKeyID = EventHotKeyID()

        gMyHotKeyID.id = UInt32(keyCode)

        // Not sure what "swat" vs "htk1" do.
        gMyHotKeyID.signature = OSType("swat".fourCharCodeValue)
        // gMyHotKeyID.signature = OSType("htk1".fourCharCodeValue)

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyReleased)

        // Install handler.
        InstallEventHandler(GetApplicationEventTarget(), {
          (nextHanlder, theEvent, userData) -> OSStatus in
          // var hkCom = EventHotKeyID()

          // GetEventParameter(theEvent,
          //                   EventParamName(kEventParamDirectObject),
          //                   EventParamType(typeEventHotKeyID),
          //                   nil,
          //                   MemoryLayout<EventHotKeyID>.size,
          //                   nil,
          //                   &hkCom)

          NSLog("Command + R Released!")

          return noErr
          /// Check that hkCom in indeed your hotkey ID and handle it.
        }, 1, &eventType, nil, nil)

        // Register hotkey.
        let status = RegisterEventHotKey(UInt32(keyCode),
                                         modifierFlags,
                                         gMyHotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &hotKeyRef)
        assert(status == noErr)
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
    
    @objc func handleScreenParameters(notification: Notification) {
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

    @objc func openWebsite() {
        NSWorkspace.shared.open(URL(string: BRIGHTINTOSH_URL)!)
    }
    
}

