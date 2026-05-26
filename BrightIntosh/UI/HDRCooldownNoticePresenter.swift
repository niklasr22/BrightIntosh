//
//  HDRCooldownNoticePresenter.swift
//  BrightIntosh
//
//  Created by Cursor on 26.05.26.
//

import Cocoa

@MainActor
final class HDRCooldownNoticePresenter {
    private var toastPanel: NSWindow?
    private var toastDismissWorkItem: DispatchWorkItem?
    
    func present(cooldownSeconds: Int, displayID: CGDirectDisplayID?, statusItem: NSStatusItem?) {
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
        
        guard let toastFrame = frameForToast(contentSize: contentSize, displayID: displayID, statusItem: statusItem) else {
            print("HDR cooldown toast: no placement (no NSScreen.main / no target); keeping any existing toast")
            return
        }
        
        dismiss()
        
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
        let closeButton = ToastCloseButton()
        closeButton.menuTarget = self
        closeButton.image = closeImage
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.bezelStyle = .shadowlessSquare
        closeButton.focusRingType = .none
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeClicked(_:))
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
        
        toastPanel = panel
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        toastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
    }
    
    private func frameForToast(contentSize: NSSize, displayID: CGDirectDisplayID?, statusItem: NSStatusItem?) -> NSRect? {
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
    
    private func dismiss() {
        toastDismissWorkItem?.cancel()
        toastDismissWorkItem = nil
        toastPanel?.orderOut(nil)
        toastPanel = nil
    }
    
    @objc private func closeClicked(_ sender: NSButton) {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            BrightIntoshSettings.shared.showHDRRetryCooldownNotice = false
        }
        dismiss()
    }
    
    @objc fileprivate func disableFromContextMenu(_ sender: NSMenuItem) {
        BrightIntoshSettings.shared.showHDRRetryCooldownNotice = false
        dismiss()
    }
}

private final class ToastCloseButton: NSButton {
    weak var menuTarget: HDRCooldownNoticePresenter?
    
    override func rightMouseDown(with event: NSEvent) {
        guard let target = menuTarget else {
            super.rightMouseDown(with: event)
            return
        }
        let menu = NSMenu()
        let item = NSMenuItem(
            title: String(localized: "Don’t show this notice again"),
            action: #selector(HDRCooldownNoticePresenter.disableFromContextMenu(_:)),
            keyEquivalent: ""
        )
        item.target = target
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
