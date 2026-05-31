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
    
    nonisolated(unsafe) private var hdrCooldownObserver: NSObjectProtocol?
    nonisolated(unsafe) private var hdrCooldownEndObserver: NSObjectProtocol?
    
    private var hdrCooldownMenuDisplayIds: Set<CGDirectDisplayID> = []
    private var hdrCooldownMenuEndDates: [CGDirectDisplayID: Date] = [:]
    private var hdrCooldownMenuSeconds: Int = 30
    private var hdrCooldownMenuRefreshTimer: Timer?
    
    private let menu: NSMenu
    private var isOpen: Bool = false
    
    // menu items
    private var titleItem: NSMenuItem!
    private var toggleTimerItem: NSMenuItem!
    private var toggleIncreasedBrightnessItem: NSMenuItem!
    private var trialExpiredItem: NSMenuItem!
    private var unsupportedDeviceItem: NSMenuItem!
    
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
    
    init(automationManager: AutomationManager, settingsWindowController: SettingsWindowController, toggleBrightIntosh: @escaping () -> ()) {
        self.toggleBrightIntosh = toggleBrightIntosh

        self.automationManager = automationManager
        self.settingsWindowController = settingsWindowController
        
        menu = NSMenu()
        menu.title = "BrightIntosh Status Bar Item"
        
        super.init()
        
        // Menu bar app
        menu.delegate = self
        menu.minimumWidth = 280
        
        titleItem = NSMenuItem(title: titleString, action: #selector(openWebsite), keyEquivalent: "")
        titleItem.image = NSImage(named: "LogoLG")
        titleItem.image?.size = CGSize(width: 28, height: 28)
        
        toggleIncreasedBrightnessItem = NSMenuItem(title: "", action: #selector(callToggleBrightIntosh), keyEquivalent: "")
        toggleIncreasedBrightnessItem.setShortcut(for: .toggleBrightIntosh)
        toggleIncreasedBrightnessItem.target = self
        
        toggleTimerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        toggleTimerItem.submenu = createTimerDurationSubmenu()
        
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
        if BrightIntoshSettings.shared.brightintoshActive {
            menu.addItem(toggleTimerItem!)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(settingsItem)
        menu.addItem(helpItem)
        menu.addItem(aboutUsItem)
        menu.addItem(quitItem)
        
        unsupportedDeviceItem = NSMenuItem(title: String(localized: "This device is incompatible"), action: nil, keyEquivalent: "")
        unsupportedDeviceItem.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "This device is incompatible")
        menu.addItem(unsupportedDeviceItem)
        
        trialExpiredItem = NSMenuItem(title: String(localized: "Your trial has expired"), action: nil, keyEquivalent: "")
        trialExpiredItem.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Your trial has expired")
        trialExpiredItem.isHidden = true
        menu.addItem(trialExpiredItem)
        
        if !BrightIntoshSettings.shared.hideMenuBarItem {
            createStatusBarItem()
        }
        
        self.updateMenu()
        
        // Listen to settings
        BrightIntoshSettings.shared.addListener(setting: "brightintoshActive") {
            if !BrightIntoshSettings.shared.brightintoshActive {
                self.hdrCooldownMenuDisplayIds.removeAll()
                self.hdrCooldownMenuEndDates.removeAll()
                self.stopHDRCooldownMenuRefreshTimer()
            }
            self.updateMenu()
        }
        
        BrightIntoshSettings.shared.addListener(setting: "timerAutomation") {
            self.updateMenu()
        }
        
        BrightIntoshSettings.shared.addListener(setting: "timerAutomationTimeout") {
            self.updateMenu()
        }
        
        BrightIntoshSettings.shared.addListener(setting: "hideMenuBarItem") {
            self.updateStatusBarItemVisibility()
        }
        
        BrightIntoshSettings.shared.addListener(setting: "ignoreMissingHDRForBrightnessFallback") {
            if BrightIntoshSettings.shared.ignoreMissingHDRForBrightnessFallback {
                self.hdrCooldownMenuDisplayIds.removeAll()
                self.hdrCooldownMenuEndDates.removeAll()
                self.stopHDRCooldownMenuRefreshTimer()
            }
            self.updateMenu()
        }
        
        hdrCooldownObserver = NotificationCenter.default.addObserver(
            forName: .brightIntoshHDRCooldownDidBegin,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let seconds = notification.userInfo?["cooldownSeconds"] as? Int ?? 30
            let displayID = (notification.userInfo?["displayID"] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
            Task { @MainActor in
                guard !BrightIntoshSettings.shared.ignoreMissingHDRForBrightnessFallback else { return }
                if let id = displayID {
                    self?.hdrCooldownMenuDisplayIds.insert(id)
                    self?.hdrCooldownMenuEndDates[id] = Date().addingTimeInterval(TimeInterval(seconds))
                    self?.hdrCooldownMenuSeconds = seconds
                }
                self?.startHDRCooldownMenuRefreshTimerIfNeeded()
                self?.updateMenu()
            }
        }
        
        hdrCooldownEndObserver = NotificationCenter.default.addObserver(
            forName: .brightIntoshHDRCooldownDidEnd,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let displayId = notification.userInfo?["displayID"] as? NSNumber
            Task { @MainActor in
                if let id = displayId.map({ CGDirectDisplayID($0.uint32Value) }) {
                    self?.hdrCooldownMenuDisplayIds.remove(id)
                    self?.hdrCooldownMenuEndDates.removeValue(forKey: id)
                }
                self?.stopHDRCooldownMenuRefreshTimerIfNeeded()
                self?.updateMenu()
            }
        }
    }
    
    deinit {
        if let hdrCooldownObserver {
            NotificationCenter.default.removeObserver(hdrCooldownObserver)
        }
        if let hdrCooldownEndObserver {
            NotificationCenter.default.removeObserver(hdrCooldownEndObserver)
        }
    }
    
    private static let hdrCooldownMenuSeparatorTag = 9_001
    private static let hdrCooldownMenuInfoTag = 9_002
    private static let incompatibleAppsMenuSeparatorTag = 9_003
    private static let incompatibleAppsMenuInfoTag = 9_004
    private static let timerDurationMinutes = Array(stride(from: 10, to: 51, by: 10)) + Array(stride(from: 60, to: 300, by: 30))
    
    private func createTimerDurationSubmenu() -> NSMenu {
        let submenu = NSMenu()
        
        if BrightIntoshSettings.shared.timerAutomation {
            submenu.addItem(createTimerDurationItem(for: 0))
        }
        
        for minutes in Self.timerDurationMinutes {
            submenu.addItem(createTimerDurationItem(for: minutes))
        }
        
        return submenu
    }
    
    private func createTimerDurationItem(for minutes: Int) -> NSMenuItem {
        let item = NSMenuItem(
            title: timerDurationTitle(for: minutes),
            action: #selector(setTimerAutomationDuration(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = minutes
        return item
    }
    
    private func timerDurationTitle(for minutes: Int) -> String {
        if minutes == 0 {
            return String(localized: "Never")
        }
        if minutes < 60 {
            return String(format: String(localized: "%d min"), minutes)
        }
        return String(format: String(localized: "%.1f h"), Double(minutes) / 60.0)
    }
    
    private func updateTimerDurationSubmenu() {
        guard let submenu = toggleTimerItem.submenu else { return }
        
        let neverItemIndex = submenu.items.firstIndex { ($0.representedObject as? Int) == 0 }
        if BrightIntoshSettings.shared.timerAutomation {
            if neverItemIndex == nil {
                submenu.insertItem(createTimerDurationItem(for: 0), at: 0)
            }
        } else if let neverItemIndex {
            submenu.removeItem(at: neverItemIndex)
        }
        
        let selectedMinutes = BrightIntoshSettings.shared.timerAutomation
            ? BrightIntoshSettings.shared.timerAutomationTimeout
            : nil
        
        submenu.items.forEach { item in
            item.state = (item.representedObject as? Int) == selectedMinutes ? .on : .off
        }
    }
    
    private func currentHDRCooldownRemainingSeconds() -> Int {
        guard !hdrCooldownMenuDisplayIds.isEmpty else { return 0 }
        let now = Date()
        let remaining = hdrCooldownMenuDisplayIds.compactMap { id -> Int? in
            guard let endDate = hdrCooldownMenuEndDates[id] else { return nil }
            return max(0, Int(ceil(endDate.timeIntervalSince(now))))
        }.max()
        return remaining ?? max(0, hdrCooldownMenuSeconds)
    }
    
    private func startHDRCooldownMenuRefreshTimerIfNeeded() {
        guard isOpen, !hdrCooldownMenuDisplayIds.isEmpty, hdrCooldownMenuRefreshTimer == nil else { return }
        hdrCooldownMenuRefreshTimer = Timer(fire: .now, interval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let now = Date()
                self.hdrCooldownMenuEndDates = self.hdrCooldownMenuEndDates.filter { _, endDate in endDate > now }
                self.hdrCooldownMenuDisplayIds = self.hdrCooldownMenuDisplayIds.filter { self.hdrCooldownMenuEndDates[$0] != nil }
                self.reconcileHDRCooldownMenuItems()
                self.stopHDRCooldownMenuRefreshTimerIfNeeded()
            }
        }
        RunLoop.main.add(hdrCooldownMenuRefreshTimer!, forMode: .eventTracking)
    }
    
    private func stopHDRCooldownMenuRefreshTimer() {
        hdrCooldownMenuRefreshTimer?.invalidate()
        hdrCooldownMenuRefreshTimer = nil
    }
    
    private func stopHDRCooldownMenuRefreshTimerIfNeeded() {
        if hdrCooldownMenuDisplayIds.isEmpty || !isOpen {
            stopHDRCooldownMenuRefreshTimer()
        }
    }
    
    private func reconcileHDRCooldownMenuItems() {
        let remainingSeconds = currentHDRCooldownRemainingSeconds()
        let infoTitle = String(format: String(localized: "Awaiting macOS EDR mode (%llds)"), Int64(remainingSeconds))
        
        guard !hdrCooldownMenuDisplayIds.isEmpty, !BrightIntoshSettings.shared.ignoreMissingHDRForBrightnessFallback else {
            for item in menu.items where item.tag == Self.hdrCooldownMenuSeparatorTag || item.tag == Self.hdrCooldownMenuInfoTag {
                menu.removeItem(item)
            }
            return
        }
        
        if let info = menu.items.first(where: { $0.tag == Self.hdrCooldownMenuInfoTag }) {
            info.title = infoTitle
            return
        }
        
        guard let titleIdx = menu.items.firstIndex(where: { $0 === titleItem }) else { return }
        
        let separator = NSMenuItem.separator()
        separator.tag = Self.hdrCooldownMenuSeparatorTag
        
        let info = NSMenuItem(title: infoTitle, action: nil, keyEquivalent: "")
        info.tag = Self.hdrCooldownMenuInfoTag
        info.isEnabled = false
        info.image = NSImage(systemSymbolName: "timer", accessibilityDescription: String(localized: "HDR retry wait"))
        info.toolTip = String(
            localized: "BrightIntosh pauses the extra brightness until macOS properly displays HDR content again."
        )
        menu.insertItem(separator, at: titleIdx + 1)
        menu.insertItem(info, at: titleIdx + 2)
    }
    
    private func incompatibleAppsTitle(_ apps: [IncompatibleRunningApp]) -> String {
        apps.map(\.displayName).joined(separator: ", ")
    }
    
    private func reconcileIncompatibleAppsMenuItems() {
        let incompatibleApps = runningIncompatibleApps()
        
        guard !incompatibleApps.isEmpty else {
            for item in menu.items where item.tag == Self.incompatibleAppsMenuSeparatorTag || item.tag == Self.incompatibleAppsMenuInfoTag {
                menu.removeItem(item)
            }
            return
        }
        
        let appList = incompatibleAppsTitle(incompatibleApps)
        let infoTitle = String(localized: "Potential conflict: \(appList)")
        
        if let info = menu.items.first(where: { $0.tag == Self.incompatibleAppsMenuInfoTag }) {
            info.title = infoTitle
            info.toolTip = String(localized: "\(appList) may also control display brightness or color and interfere with BrightIntosh.")
            return
        }
        
        guard let titleIdx = menu.items.firstIndex(where: { $0 === titleItem }) else { return }
        
        let separator = NSMenuItem.separator()
        separator.tag = Self.incompatibleAppsMenuSeparatorTag
        
        let info = NSMenuItem(title: infoTitle, action: nil, keyEquivalent: "")
        info.tag = Self.incompatibleAppsMenuInfoTag
        info.isEnabled = false
        info.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: String(localized: "Potential conflict"))
        info.toolTip = String(localized: "\(appList) may also control display brightness or color and interfere with BrightIntosh.")
        menu.insertItem(separator, at: titleIdx + 1)
        menu.insertItem(info, at: titleIdx + 2)
    }
    
    private func createStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.menu = menu
    }
    
    func updateMenu() {
        guard let statusItem else { return }
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: BrightIntoshSettings.shared.brightintoshActive ? "sun.max.circle.fill" : "sun.max.circle", accessibilityDescription: BrightIntoshSettings.shared.brightintoshActive ? "Increased brightness" : "Default brightness")
            button.toolTip = titleString
        }
        
        toggleIncreasedBrightnessItem.title = BrightIntoshSettings.shared.brightintoshActive ? String(localized: "Deactivate") : String(localized: "Activate")
        toggleTimerItem.title = BrightIntoshSettings.shared.timerAutomation ? String(localized: "Disable after") : String(localized: "Enable Timer")
        updateTimerDurationSubmenu()
        if #available(macOS 14, *), !BrightIntoshSettings.shared.timerAutomation {
            toggleTimerItem.badge = nil
        }
        
        reconcileHDRCooldownMenuItems()
        reconcileIncompatibleAppsMenuItems()
        
        if BrightIntoshSettings.shared.brightintoshActive {
            if !menu.items.contains(toggleTimerItem) {
                let afterToggle = (menu.items.firstIndex(where: { $0 === toggleIncreasedBrightnessItem }) ?? 0) + 1
                menu.insertItem(toggleTimerItem!, at: afterToggle)
            }
        } else if menu.items.contains(toggleTimerItem) {
            menu.removeItem(toggleTimerItem!)
        }
        
        trialExpiredItem.isHidden = Authorizer.shared.isAllowed()
        
        unsupportedDeviceItem.isHidden = isSetupSupported()
    }
    
    func updateStatusBarItemVisibility() {
        if BrightIntoshSettings.shared.hideMenuBarItem {
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
    
    @objc func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindowController.showWindow(self)
    }
    
    @objc func setTimerAutomationDuration(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        
        if minutes == 0 {
            BrightIntoshSettings.shared.timerAutomation = false
            BrightIntoshSettings.shared.timerAutomationTimeout = 0
        } else {
            BrightIntoshSettings.shared.timerAutomationTimeout = minutes
            BrightIntoshSettings.shared.timerAutomation = true
        }
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
                self.toggleTimerItem!.badge = NSMenuItemBadge(string: timerString)
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
        isOpen = true
        startTimePollerIfApplicable()
        startHDRCooldownMenuRefreshTimerIfNeeded()
        updateMenu()
    }
    
    func startTimePollerIfApplicable() {
        if BrightIntoshSettings.shared.timerAutomation {
            self.startRemainingTimePoller()
        } else if !BrightIntoshSettings.shared.timerAutomation {
            self.stopRemainingTimePoller()
        }
    }
    
    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
        self.stopRemainingTimePoller()
        stopHDRCooldownMenuRefreshTimer()
    }
}
