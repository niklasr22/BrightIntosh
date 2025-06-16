//
//  StatusBarMenu.swift
//  BrightIntosh
//
//  Created by Johanna Schwarz on 29.02.24.
//

import Cocoa
import KeyboardShortcuts

@MainActor
class StatusBarMenu : NSObject, NSMenuDelegate {
    
    private var supportedDevice: Bool = false
    private var automationManager: AutomationManager
    private var settingsWindowController: SettingsWindowController
    
    @objc private var toggleBrightIntosh: () -> ()
    
    private var statusItem: NSStatusItem?
    
    private let menu: NSMenu
    private var isOpen: Bool = false
    
    // menu items
    private var titleItem: NSMenuItem!
    private var toggleTimerItem: NSMenuItem!
    private var toggleIncreasedBrightnessItem: NSMenuItem!
    private var trialExpiredItem: NSMenuItem!
    private var brightnessSlider: NSSlider!
    private var brightnessValueDisplay: NSTextField!
    
    private var remainingTimePoller: Timer?
    
#if STORE && DEBUG
    private let titleString = "BrightIntosh SE (v\(appVersion)-dev)"
#elseif STORE
    private let titleString = "BrightIntosh SE (v\(appVersion))"
#elseif DEBUG
    private let titleString = "BrightIntosh (v\(appVersion)-dev)"
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
        menu.delegate = self
        menu.minimumWidth = 280
        
        titleItem = NSMenuItem(title: titleString, action: #selector(openWebsite), keyEquivalent: "")
        
        let brightnessSliderElements = createBrightnessSliderItem()
        let brightnessSliderItem = brightnessSliderElements.0
        brightnessSlider = brightnessSliderElements.1
        brightnessValueDisplay = brightnessSliderElements.2
        
        toggleIncreasedBrightnessItem = NSMenuItem(title: "", action: #selector(callToggleBrightIntosh), keyEquivalent: "")
        toggleIncreasedBrightnessItem.setShortcut(for: .toggleBrightIntosh)
        toggleIncreasedBrightnessItem.target = self
        
        toggleTimerItem = NSMenuItem(title: "", action: #selector(toggleTimerAutomation), keyEquivalent: "")
        toggleTimerItem.target = self
        
        let settingsItem = NSMenuItem(title: String(localized: "Settings"), action: #selector(openSettings), keyEquivalent: "")
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: String(localized: "Settings"))
        settingsItem.setShortcut(for: .openSettings)
        settingsItem.target = self
        
        let aboutUsItem = NSMenuItem(title: String(localized: "About us"), action: #selector(openLegalNotice), keyEquivalent: "")
        aboutUsItem.target = self
        
        let helpItem = NSMenuItem(title: String(localized: "Help"), action: #selector(openHelp), keyEquivalent: "")
        helpItem.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: String(localized: "Help"))
        helpItem.target = self
        
        let quitItem = NSMenuItem(title: String(localized: "Quit"), action: #selector(exitBrightIntosh), keyEquivalent: "")
        quitItem.target = self
        
        menu.addItem(titleItem)
        menu.addItem(toggleIncreasedBrightnessItem)
        if Settings.shared.brightintoshActive {
            menu.addItem(toggleTimerItem!)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Brightness:"), action: nil, keyEquivalent: ""))
        menu.addItem(brightnessSliderItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(settingsItem)
        menu.addItem(helpItem)
        menu.addItem(aboutUsItem)
        menu.addItem(quitItem)
        if !supportedDevice {
            let unsupportedDeviceItem = NSMenuItem(title: String(localized: "This device is incompatible"), action: nil, keyEquivalent: "")
            unsupportedDeviceItem.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "This device is incompatible")
            menu.addItem(unsupportedDeviceItem)
        }
        
        trialExpiredItem = NSMenuItem(title: String(localized: "Your trial has expired"), action: nil, keyEquivalent: "")
        trialExpiredItem.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Your trial has expired")
        trialExpiredItem.isHidden = true
        menu.addItem(trialExpiredItem)
        
        if !Settings.shared.hideMenuBarItem {
            createStatusBarItem()
        }
        
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
        
        Settings.shared.addListener(setting: "hideMenuBarItem") {
            self.updateStatusBarItemVisibility()
        }
    }
    
    private func createStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.menu = menu
    }
    
    private func createBrightnessSliderItem() -> (NSMenuItem, NSSlider, NSTextField) {
        let brightnessSliderItem = NSMenuItem()
        
        let sliderContainerView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 35))
        let sliderWidth = 190.0
        let sliderHeight = 30.0
        let horizontalOffset = 15.0
        let sliderY = (sliderContainerView.frame.height - sliderHeight) / 2
        
        //let brightnessSlider = StyledSlider(value: Double(Settings.shared.brightness), minValue: 1.0, maxValue: Double(getDeviceMaxBrightness()), target: self, action: #selector(brightnessSliderMoved))
        let brightnessSlider = NSSlider(value: Double(Settings.shared.brightness), minValue: 1.0, maxValue: Double(getDeviceMaxBrightness()), target: self, action: #selector(brightnessSliderMoved))
        brightnessSlider.target = self
        brightnessSlider.frame = NSRect(x: horizontalOffset, y: sliderY, width: sliderWidth, height: sliderHeight)
        brightnessSlider.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        
        let brightnessValueDisplay = NSTextField(string: "100%")
        brightnessValueDisplay.isEditable = false
        brightnessValueDisplay.isBordered = false
        brightnessValueDisplay.isSelectable = false
        brightnessValueDisplay.drawsBackground = false
        brightnessValueDisplay.setFrameOrigin(NSPoint(x: sliderContainerView.frame.width - horizontalOffset - brightnessValueDisplay.frame.width, y: sliderContainerView.frame.height / 2.0 - brightnessValueDisplay.frame.height / 2.0))
        
        sliderContainerView.addSubview(brightnessSlider)
        sliderContainerView.addSubview(brightnessValueDisplay)
        brightnessSliderItem.view = sliderContainerView
        return (brightnessSliderItem, brightnessSlider, brightnessValueDisplay)
    }
    
    func updateMenu() {
        guard let statusItem else { return }
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: Settings.shared.brightintoshActive ? "sun.max.circle.fill" : "sun.max.circle", accessibilityDescription: Settings.shared.brightintoshActive ? "Increased brightness" : "Default brightness")
            button.toolTip = titleString
        }
        
        toggleIncreasedBrightnessItem.title = Settings.shared.brightintoshActive ? String(localized: "Deactivate") : String(localized: "Activate")
        toggleTimerItem.title = Settings.shared.timerAutomation ? String(localized: "Disable Timer") : String(localized: "Enable Timer")
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
        brightnessValueDisplay.stringValue = "\(Int(round(brightnessSlider.getNormalizedSliderValue() * 100.0)))%"
        
        self.trialExpiredItem.isHidden = Authorizer.shared.isAllowed()
    }
    
    func updateStatusBarItemVisibility() {
        if Settings.shared.hideMenuBarItem {
            if let statusItem = statusItem {
                statusItem.menu = nil
                NSStatusBar.system.removeStatusItem(statusItem)
            }
        } else {
            createStatusBarItem()
            updateMenu()
        }
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
        NSWorkspace.shared.open(BrightIntoshUrls.web)
    }
    
    @objc func openHelp() {
        NSWorkspace.shared.open(BrightIntoshUrls.help)
    }
    
    @objc func openLegalNotice() {
        NSWorkspace.shared.open(BrightIntoshUrls.legal)
    }
    
    func startRemainingTimePoller() {
        if self.remainingTimePoller != nil {
            return
        }
        
        self.remainingTimePoller = Timer(fire: Date.now, interval: 1.0, repeats: true, block: {t in
            Task { @MainActor in
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
                    self.toggleTimerItem!.title = String(localized: "Disable Timer") + timerString
                }
            }
        })
        
        RunLoop.main.add(self.remainingTimePoller!, forMode: RunLoop.Mode.eventTracking)
    }
    
    func stopRemainingTimePoller() {
        if remainingTimePoller == nil {
            return
        }
        self.remainingTimePoller?.invalidate()
        self.remainingTimePoller = nil
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        startTimePollerIfApplicable()
        updateMenu()
        isOpen = true
    }
    
    func startTimePollerIfApplicable() {
        if Settings.shared.timerAutomation {
            self.startRemainingTimePoller()
        } else if !Settings.shared.timerAutomation {
            self.stopRemainingTimePoller()
        }
    }
    
    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
        self.stopRemainingTimePoller()
    }
}
