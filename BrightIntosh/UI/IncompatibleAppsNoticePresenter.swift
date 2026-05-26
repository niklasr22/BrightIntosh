//
//  IncompatibleAppsNoticePresenter.swift
//  BrightIntosh
//
//  Created by Cursor on 26.05.26.
//

import Cocoa

@MainActor
final class IncompatibleAppsNoticePresenter {
    private var toastPanel: NSWindow?
    private var toastDismissWorkItem: DispatchWorkItem?
    private var lastPresentedAppNames: Set<String> = []
    
    func resetPresentedApps() {
        lastPresentedAppNames.removeAll()
    }
    
    func scheduleIfNeeded(statusItem: NSStatusItem?) {
        Task { @MainActor in
            await Task.yield()
            self.presentIfNeeded(statusItem: statusItem)
        }
    }
    
    func scheduleIfNeeded() {
        scheduleIfNeeded(statusItem: nil)
    }
    
    private func presentIfNeeded(statusItem: NSStatusItem?) {
        guard BrightIntoshSettings.shared.brightintoshActive,
              BrightIntoshSettings.shared.showIncompatibleAppsNotice else {
            return
        }
        
        let incompatibleApps = runningIncompatibleApps()
        guard !incompatibleApps.isEmpty else {
            resetPresentedApps()
            return
        }
        
        let appNames = Set(incompatibleApps.map(\.displayName))
        guard appNames != lastPresentedAppNames else {
            return
        }
        
        if presentToast(apps: incompatibleApps, statusItem: statusItem) {
            lastPresentedAppNames = appNames
        }
    }
    
    private func incompatibleAppsTitle(_ apps: [IncompatibleRunningApp]) -> String {
        apps.map(\.displayName).joined(separator: ", ")
    }
    
    private func frameForToast(contentSize: NSSize, statusItem: NSStatusItem?) -> NSRect? {
        let margin: CGFloat = 12
        let gapFromTop: CGFloat = 16
        
        if let button = statusItem?.button, let anchorWindow = button.window,
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
    
    private func dismissToast() {
        toastDismissWorkItem?.cancel()
        toastDismissWorkItem = nil
        toastPanel?.orderOut(nil)
        toastPanel = nil
    }
    
    @objc private func closeClicked(_ sender: NSButton) {
        dismissToast()
    }
    
    private func presentToast(apps: [IncompatibleRunningApp], statusItem: NSStatusItem?) -> Bool {
        let appList = incompatibleAppsTitle(apps)
        let message = String(
            localized: "\(appList) may interfere with BrightIntosh because it can also adjust display brightness or color."
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
        
        guard let toastFrame = frameForToast(contentSize: contentSize, statusItem: statusItem) else {
            print("Incompatible apps toast: no placement (no NSScreen.main / no status item); keeping any existing toast")
            return false
        }
        
        dismissToast()
        
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.hudWindow, .borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.backgroundColor = .clear
        panel.hasShadow = true
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
        let warningImage = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: String(localized: "Potential conflict"))?
            .withSymbolConfiguration(symbolConfig)
        let iconView = NSImageView()
        iconView.image = warningImage
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
        let closeButton = NSButton()
        closeButton.image = closeImage
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.bezelStyle = .shadowlessSquare
        closeButton.focusRingType = .none
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeClicked(_:))
        closeButton.toolTip = String(localized: "Click to dismiss.")
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
        
        toastPanel = panel
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismissToast()
        }
        toastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
        return true
    }
}
