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
    // Store reference to slider container for resizing
    private var sliderContainerViewRef: NSView?
    
    private var supportedDevice: Bool = false
    private var automationManager: AutomationManager
    private var settingsWindowController: SettingsWindowController
    
    @objc private var toggleBrightIntosh: () -> ()
    
    private var statusItem: NSStatusItem?
    private var hdrCooldownToastPanel: NSWindow?
    private var hdrCooldownToastDismissWorkItem: DispatchWorkItem?
    /// Observer token; `nonisolated(unsafe)` so `deinit` can remove it (token is safe to pass to `removeObserver`).
    nonisolated(unsafe) private var hdrCooldownObserver: NSObjectProtocol?
    nonisolated(unsafe) private var hdrCooldownEndObserver: NSObjectProtocol?
    
    /// Displays currently in the HDR retry sleep (mirrors `GammaTechnique.displaysPendingHDRRetry` via notifications).
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
    private var brightnessSlider: NSSlider!
    private var brightnessValueDisplay: NSTextField!
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
        
        let brightnessSliderElements = createBrightnessSliderItem()
        let brightnessSliderItem = brightnessSliderElements.0
        brightnessSlider = brightnessSliderElements.1
        brightnessValueDisplay = brightnessSliderElements.2
        
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
        menu.addItem(NSMenuItem(title: String(localized: "Brightness:"), action: nil, keyEquivalent: ""))
        menu.addItem(brightnessSliderItem)
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
        
        BrightIntoshSettings.shared.addListener(setting: "brightness") {
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
        
        hdrCooldownObserver = NotificationCenter.default.addObserver(
            forName: .brightIntoshHDRCooldownDidBegin,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let seconds = notification.userInfo?["cooldownSeconds"] as? Int ?? 30
            let displayID = (notification.userInfo?["displayID"] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
            Task { @MainActor in
                if let id = displayID {
                    self?.hdrCooldownMenuDisplayIds.insert(id)
                    self?.hdrCooldownMenuEndDates[id] = Date().addingTimeInterval(TimeInterval(seconds))
                    self?.hdrCooldownMenuSeconds = seconds
                }
                self?.startHDRCooldownMenuRefreshTimerIfNeeded()
                self?.updateMenu()
                if BrightIntoshSettings.shared.showHDRRetryCooldownNotice {
                    self?.presentHDRCooldownToast(cooldownSeconds: seconds, displayID: displayID)
                }
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
        for item in menu.items where item.tag == Self.hdrCooldownMenuSeparatorTag || item.tag == Self.hdrCooldownMenuInfoTag {
            menu.removeItem(item)
        }
        guard !hdrCooldownMenuDisplayIds.isEmpty else { return }
        guard let titleIdx = menu.items.firstIndex(where: { $0 === titleItem }) else { return }
        
        let separator = NSMenuItem.separator()
        separator.tag = Self.hdrCooldownMenuSeparatorTag
        let remainingSeconds = currentHDRCooldownRemainingSeconds()
        let info = NSMenuItem(
            title: String(format: String(localized: "Awaiting macOS EDR mode (%llds)"), Int64(remainingSeconds)),
            action: nil,
            keyEquivalent: ""
        )
        info.tag = Self.hdrCooldownMenuInfoTag
        info.isEnabled = false
        info.image = NSImage(systemSymbolName: "timer", accessibilityDescription: String(localized: "HDR retry wait"))
        info.toolTip = String(
            localized: "BrightIntosh pauses the extra brightness until macOS properly displays HDR content again."
        )
        menu.insertItem(separator, at: titleIdx + 1)
        menu.insertItem(info, at: titleIdx + 2)
    }
    
    private func createStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.menu = menu
    }
    
    private func dismissHDRCooldownToast() {
        hdrCooldownToastDismissWorkItem?.cancel()
        hdrCooldownToastDismissWorkItem = nil
        hdrCooldownToastPanel?.orderOut(nil)
        hdrCooldownToastPanel = nil
    }
    
    @objc private func hdrCooldownToastCloseClicked(_ sender: NSButton) {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            BrightIntoshSettings.shared.showHDRRetryCooldownNotice = false
        }
        dismissHDRCooldownToast()
    }
    
    @objc fileprivate func hdrCooldownToastDisableFromContextMenu(_ sender: NSMenuItem) {
        BrightIntoshSettings.shared.showHDRRetryCooldownNotice = false
        dismissHDRCooldownToast()
    }
    
    /// Resolves on-screen frame before creating a window so we never dismiss an existing toast unless the new one can be shown.
    private func frameForHDRCooldownToast(contentSize: NSSize, displayID: CGDirectDisplayID?) -> NSRect? {
        let margin: CGFloat = 12
        let gapFromTop: CGFloat = 16
        let targetScreen = displayID.flatMap { id in NSScreen.screens.first { $0.displayId == id } }
        if let screen = targetScreen {
            let vf = screen.visibleFrame
            var originX = vf.midX - contentSize.width / 2
            let originY = vf.maxY - gapFromTop - contentSize.height
            originX = min(max(originX, vf.minX + margin), vf.maxX - contentSize.width - margin)
            return NSRect(x: originX, y: originY, width: contentSize.width, height: contentSize.height)
        }
        if let statusItem, let button = statusItem.button, let anchorWindow = button.window,
           !BrightIntoshSettings.shared.hideMenuBarItem {
            let buttonRectOnScreen = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
            var originX = buttonRectOnScreen.midX - contentSize.width / 2
            let originY = buttonRectOnScreen.minY - 10 - contentSize.height
            if let screen = anchorWindow.screen ?? NSScreen.main {
                let vf = screen.visibleFrame
                originX = min(max(originX, vf.minX + margin), vf.maxX - contentSize.width - margin)
            }
            return NSRect(x: originX, y: originY, width: contentSize.width, height: contentSize.height)
        }
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            var originX = vf.midX - contentSize.width / 2
            let originY = vf.maxY - gapFromTop - contentSize.height
            originX = min(max(originX, vf.minX + margin), vf.maxX - contentSize.width - margin)
            return NSRect(x: originX, y: originY, width: contentSize.width, height: contentSize.height)
        }
        return nil
    }
    
    /// Frosted banner on the display that entered cooldown. Stays visible when clicking the desktop (does not hide on deactivate). Only the close button or auto-dismiss clears it.
    private func presentHDRCooldownToast(cooldownSeconds: Int, displayID: CGDirectDisplayID?) {
        guard BrightIntoshSettings.shared.showHDRRetryCooldownNotice else { return }
        
        let message = String(
            localized: "macOS is temporarily limiting the display's maximum brightness. Brightintosh will restore the boost in approx. \(cooldownSeconds) seconds once the system allows it."
        )
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let panelWidth: CGFloat = 280
        let horizontalPadding: CGFloat = 14
        let verticalPadding: CGFloat = 12
        let iconSide: CGFloat = 16
        let iconTextGap: CGFloat = 8
        let closeSide: CGFloat = 22
        let closeLeadingGap: CGFloat = 6
        let textWidth = panelWidth - horizontalPadding * 2 - iconSide - iconTextGap - closeLeadingGap - closeSide
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        let textRect = (message as NSString).boundingRect(
            with: NSSize(width: textWidth, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let contentHeight = ceil(textRect.height) + verticalPadding * 2
        let contentSize = NSSize(width: panelWidth, height: contentHeight)
        
        guard let toastFrame = frameForHDRCooldownToast(contentSize: contentSize, displayID: displayID) else {
            print("HDR cooldown toast: no placement (no NSScreen.main / no target); keeping any existing toast")
            return
        }
        
        dismissHDRCooldownToast()
        
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.hudWindow, .borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Slightly above default status-bar level so the toast isn’t covered; still a floating non-activating panel.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false
        
        var effect: NSView!
        
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 20.0
            glass.frame = NSRect(origin: .zero, size: contentSize)
            glass.autoresizingMask = [.width, .height]
            effect = glass
        } else {
            panel.hasShadow = false
            let fallback = NSVisualEffectView(frame: NSRect(origin: .zero, size: contentSize))
            fallback.autoresizingMask = [.width, .height]
            fallback.material = .popover
            fallback.blendingMode = .behindWindow
            fallback.state = .active
            fallback.wantsLayer = true
            fallback.layer?.cornerRadius = 16
            if #available(macOS 11.0, *) {
                fallback.layer?.cornerCurve = .continuous
            }
            effect = fallback
        }
        
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: iconSide - 2, weight: .medium)
        let timerImage = NSImage(systemSymbolName: "timer", accessibilityDescription: String(localized: "Short wait"))?
            .withSymbolConfiguration(symbolConfig)
        let iconView = NSImageView()
        iconView.image = timerImage
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = font
        label.textColor = .labelColor
        label.alignment = .natural
        label.preferredMaxLayoutWidth = textWidth
        label.isEditable = false
        label.isSelectable = false
        label.refusesFirstResponder = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        
        let closeConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        let closeImage = NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "Dismiss notice"))?
            .withSymbolConfiguration(closeConfig)
        let closeButton = HDRToastCloseButton()
        closeButton.menuTarget = self
        closeButton.image = closeImage
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.bezelStyle = .shadowlessSquare
        closeButton.focusRingType = .none
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(hdrCooldownToastCloseClicked(_:))
        closeButton.toolTip = String(
            localized: "Click to dismiss. Option-click to dismiss and stop showing these notices. Control-click for a menu."
        )
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        
        effect.addSubview(iconView)
        effect.addSubview(label)
        effect.addSubview(closeButton)
        panel.contentView = effect
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: horizontalPadding),
            iconView.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSide),
            iconView.heightAnchor.constraint(equalToConstant: iconSide),
            
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: iconTextGap),
            label.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -closeLeadingGap),
            label.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            
            closeButton.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -horizontalPadding + 2),
            closeButton.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: closeSide),
            closeButton.heightAnchor.constraint(equalToConstant: closeSide),
        ])
        
        panel.setFrame(toastFrame, display: false)
        panel.orderFrontRegardless()
        
        hdrCooldownToastPanel = panel
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismissHDRCooldownToast()
        }
        hdrCooldownToastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
    }
    
    private func createBrightnessSliderItem() -> (NSMenuItem, NSSlider, NSTextField) {
        let brightnessSliderItem = NSMenuItem()

        let minWidth = menu.minimumWidth
        let containerHeight: CGFloat = 30.0
        let sliderContainerView = NSView(frame: NSRect(x: 0, y: 0, width: minWidth, height: containerHeight))
        self.sliderContainerViewRef = sliderContainerView

        let brightnessSlider = if #available(macOS 26.0, *) {
            NSSlider(value: Double(BrightIntoshSettings.shared.brightness), minValue: 0.0, maxValue: 1.0, target: self, action: #selector(brightnessSliderMoved))
        } else {
            StyledSlider(value: Double(BrightIntoshSettings.shared.brightness), minValue: 0.0, maxValue: 1.0, target: self, action: #selector(brightnessSliderMoved))
        }
        brightnessSlider.target = self
        sliderContainerView.addSubview(brightnessSlider)

        let brightnessValueDisplay = NSTextField(string: "100%")
        brightnessValueDisplay.alignment = .right
        brightnessValueDisplay.isEditable = false
        brightnessValueDisplay.isBordered = false
        brightnessValueDisplay.isSelectable = false
        brightnessValueDisplay.drawsBackground = false
        sliderContainerView.addSubview(brightnessValueDisplay)

        layoutSliderAndValueDisplay(in: sliderContainerView)
        brightnessSliderItem.view = sliderContainerView
        return (brightnessSliderItem, brightnessSlider, brightnessValueDisplay)
    }

    private func updateSliderContainerWidth() {
        guard let sliderContainerView = self.sliderContainerViewRef else { return }
        let menuWidth = max(menu.size.width, menu.minimumWidth)
        var frame = sliderContainerView.frame
        frame.size.width = menuWidth
        sliderContainerView.frame = frame

        layoutSliderAndValueDisplay(in: sliderContainerView)
    }

    private func layoutSliderAndValueDisplay(in container: NSView) {
        let horizontalOffset = 15.0
        var valueX = 0.0
        if let brightnessValueDisplay = container.subviews.first(where: { $0 is NSTextField }) as? NSTextField {
            let valueFont = brightnessValueDisplay.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let maxValueString = "100%" as NSString
            let valueAttributes: [NSAttributedString.Key: Any] = [.font: valueFont]
            let valueSize = maxValueString.size(withAttributes: valueAttributes)
            let valueWidth = ceil(valueSize.width) + 5.0
            let valueHeight = ceil(valueSize.height)
            valueX = container.frame.width - horizontalOffset - valueWidth
            let valueY = (container.frame.height - valueHeight) / 2.0
            brightnessValueDisplay.frame = NSRect(x: valueX, y: valueY, width: valueWidth, height: valueHeight)
        }
        let sliderWidth = valueX - horizontalOffset * 2.0
        let sliderHeight = 30.0
        let sliderY = (container.frame.height - sliderHeight) / 2
        if let brightnessSlider = container.subviews.first(where: { $0 is NSSlider }) as? NSSlider {
            brightnessSlider.frame = NSRect(x: horizontalOffset, y: sliderY, width: sliderWidth, height: sliderHeight)
        }
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
        
        if BrightIntoshSettings.shared.brightintoshActive {
            if !menu.items.contains(toggleTimerItem) {
                let afterToggle = (menu.items.firstIndex(where: { $0 === toggleIncreasedBrightnessItem }) ?? 0) + 1
                menu.insertItem(toggleTimerItem!, at: afterToggle)
            }
        } else if menu.items.contains(toggleTimerItem) {
            menu.removeItem(toggleTimerItem!)
        }
        
        brightnessSlider.floatValue = BrightIntoshSettings.shared.brightness
        brightnessValueDisplay.stringValue = "\(Int(round(brightnessSlider.getNormalizedSliderValue() * 100.0)))%"
        
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
    
    @objc func brightnessSliderMoved(slider: NSSlider) {
        BrightIntoshSettings.shared.brightness = slider.floatValue
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
        updateSliderContainerWidth()
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

// MARK: - HDR cooldown toast close button

private final class HDRToastCloseButton: NSButton {
    weak var menuTarget: StatusBarMenu?
    
    override func rightMouseDown(with event: NSEvent) {
        guard let target = menuTarget else {
            super.rightMouseDown(with: event)
            return
        }
        let menu = NSMenu()
        let item = NSMenuItem(
            title: String(localized: "Don’t show this notice again"),
            action: #selector(StatusBarMenu.hdrCooldownToastDisableFromContextMenu(_:)),
            keyEquivalent: ""
        )
        item.target = target
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
