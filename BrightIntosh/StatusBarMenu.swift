//
//  StatusBarMenu.swift
//  BrightIntosh
//
//  Created by Johanna Schwarz on 29.02.24.
//

import Cocoa
import KeyboardShortcuts

class StatusBarMenu : NSObject, NSMenuDelegate {
    
    private var supportedDevice: Bool = false
    private var automationManager: AutomationManager
    private var settingsWindowController: SettingsWindowController
    
    @objc private var toggleBrightIntosh: () -> ()
    
    
#if !STORE
    private let BRIGHTINTOSH_URL = "https://brightintosh.de"
#else
    private let BRIGHTINTOSH_URL = "https://brightintosh.de/index_nd.html"
#endif
    
    
    private var statusItem: NSStatusItem!
    
    private let menu: NSMenu
    
    // menu items
    private var titleItem: NSMenuItem!
    private var toggleTimerItem: NSMenuItem!
    private var toggleIncreasedBrightnessItem: NSMenuItem!
    private var brightnessSlider: NSSlider!

    
    private var remainingTimePoller: Timer?
    
#if STORE
    private let titleString = "BrightIntosh SE (v\(appVersion))"
#else
    private let titleString = "BrightIntosh (v\(appVersion))"
#endif
    
    init(supportedDevice: Bool, automationManager: AutomationManager, settingsWindowController: SettingsWindowController, toggleBrightIntosh: @escaping () -> ()) {
        self.toggleBrightIntosh = toggleBrightIntosh
        
        self.supportedDevice = supportedDevice
        self.automationManager = automationManager
        self.settingsWindowController = settingsWindowController
        
        menu = NSMenu()
        
        super.init()
        
        // Menu bar app
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        menu.delegate = self
        menu.minimumWidth = 210
        
        titleItem = NSMenuItem(title: titleString, action: #selector(openWebsite), keyEquivalent: "")
        
        // centered brightness slider
        let brightnessSliderItem = NSMenuItem()
        
        let sliderContainerView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 35))
        let horizontalPadding: CGFloat = 5.0
        let sliderWidth = sliderContainerView.frame.width - (2 * horizontalPadding)
        let sliderHeight = 30.0
        let sliderX = (sliderContainerView.frame.width - sliderWidth) / 2
        let sliderY = (sliderContainerView.frame.height - sliderHeight) / 2
        
        brightnessSlider = NSSlider(value: Double(Settings.shared.brightness), minValue: 1.0, maxValue: Double(getDeviceMaxBrightness()), target: self, action: #selector(brightnessSliderMoved))
        brightnessSlider.target = self
        brightnessSlider.frame = NSRect(x: sliderX, y: sliderY, width: sliderWidth, height: sliderHeight)
        brightnessSlider.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        sliderContainerView.addSubview(brightnessSlider)
        sliderContainerView.autoresizingMask = [.width]
        brightnessSliderItem.view = sliderContainerView
        
        
        toggleIncreasedBrightnessItem = NSMenuItem(title: "", action: #selector(callToggleBrightIntosh), keyEquivalent: "")
        toggleIncreasedBrightnessItem.setShortcut(for: .toggleBrightIntosh)
        toggleIncreasedBrightnessItem.target = self
        
        toggleTimerItem = NSMenuItem(title: "", action: #selector(toggleTimerAutomation), keyEquivalent: "")
        toggleTimerItem.target = self
        
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(exitBrightIntosh), keyEquivalent: "")
        quitItem.target = self
        
        menu.addItem(titleItem)
        menu.addItem(toggleIncreasedBrightnessItem)
        if Settings.shared.brightintoshActive {
            menu.addItem(toggleTimerItem!)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Brightness:", action: nil, keyEquivalent: ""))
        menu.addItem(brightnessSliderItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(settingsItem)
        menu.addItem(quitItem)
        if !supportedDevice {
            let unsupportedDeviceItem = NSMenuItem(title: "This device is incompatible", action: nil, keyEquivalent: "")
            unsupportedDeviceItem.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "This device is incompatible")
            menu.addItem(unsupportedDeviceItem)
        }
        
        statusItem.menu = menu
        self.updateMenu()
        
        // Listen to settings
        Settings.shared.addListener(setting: "brightintoshActive") {
            self.updateMenu()
        }
        
        Settings.shared.addListener(setting: "brightness") {
            self.updateMenu()
        }
        
        Settings.shared.addListener(setting: "timerAutomation") {
            self.updateMenu()
        }
    }
    
    func updateMenu() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: Settings.shared.brightintoshActive ? "sun.max.circle.fill" : "sun.max.circle", accessibilityDescription: Settings.shared.brightintoshActive ? "Increased brightness" : "Default brightness")
            button.toolTip = titleString
        }
        
        toggleIncreasedBrightnessItem.title = Settings.shared.brightintoshActive ? "Deactivate" : "Activate"
        toggleTimerItem.title = Settings.shared.timerAutomation ? "Disable Timer" : "Enable Timer"
        if #available(macOS 14, *), !Settings.shared.timerAutomation {
            toggleTimerItem.badge = nil
        }
        
        if Settings.shared.brightintoshActive {
            if !menu.items.contains(toggleTimerItem) {
                menu.insertItem(toggleTimerItem!, at: 2)
            }
        } else if menu.items.contains(toggleTimerItem) {
            menu.removeItem(toggleTimerItem!)
        }
        
        brightnessSlider.floatValue = Settings.shared.brightness
    }
    
    @objc func callToggleBrightIntosh() {
        toggleBrightIntosh()
    }
    
    @objc func exitBrightIntosh() {
        exit(0)
    }
    
    @objc func brightnessSliderMoved(slider: NSSlider) {
        Settings.shared.brightness = slider.floatValue
    }
    
    @objc func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindowController.showWindow(self)
    }
    
    @objc func toggleTimerAutomation() {
        Settings.shared.timerAutomation.toggle()
    }
    
    @objc func openWebsite() {
        NSWorkspace.shared.open(URL(string: BRIGHTINTOSH_URL)!)
    }
    
    func startRemainingTimePoller() {
        if self.remainingTimePoller != nil {
            return
        }
        
        self.remainingTimePoller = Timer(fire: Date.now, interval: 1.0, repeats: true, block: {t in
            let remainingTime = max(0.0, self.automationManager.getRemainingTime())
        
            if remainingTime == 0 {
                self.stopRemainingTimePoller()
                
                self.updateMenu()
                return
            }
            
            let remainingHours = Int((remainingTime / 60).rounded(.down))
            let remainingMinutes = Int(remainingTime.rounded(.down)) - (remainingHours * 60)
            let remainingSeconds = Int((remainingTime - Double(Int(remainingTime))) * 60)
            let timerString = remainingHours == 0 ? String(format: "%02d:%02d", remainingMinutes, remainingSeconds) : String(format: "%02d:%02d:%02d", remainingHours, remainingMinutes, remainingSeconds)
            if #available(macOS 14, *) {
                self.toggleTimerItem!.badge = NSMenuItemBadge(string: timerString)
            } else {
                self.toggleTimerItem!.title = "Disable Timer" + timerString
            }
        })
        
        RunLoop.main.add(self.remainingTimePoller!, forMode: RunLoop.Mode.common)
    }
    
    func stopRemainingTimePoller() {
        if remainingTimePoller == nil {
            return
        }
        self.remainingTimePoller?.invalidate()
        self.remainingTimePoller = nil
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        KeyboardShortcuts.isEnabled = false
        if Settings.shared.timerAutomation {
            self.startRemainingTimePoller()
        } else if !Settings.shared.timerAutomation {
            self.stopRemainingTimePoller()
        }
    }
    
    func menuDidClose(_ menu: NSMenu) {
        KeyboardShortcuts.isEnabled = true
        self.stopRemainingTimePoller()
    }
}
