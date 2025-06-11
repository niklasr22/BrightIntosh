//
//  OverlayWindow.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 13.07.23.
//

import Cocoa
import OSLog

let overlayLogger = Logger(
    subsystem: "Overlay Window",
    category: "Core"
)

class OverlayWindow: NSWindow {
    
    var overlay: Overlay?
    var fullsize: Bool
    
    init(fullsize: Bool = false) {
        self.fullsize = fullsize
        let rect = NSRect(x: 0, y: 0, width: 100, height: 100)
        
        
        if fullsize {
            super.init(contentRect: rect, styleMask: [.fullSizeContentView, .borderless], backing: .buffered, defer: false)
            if #available(macOS 13.0, *) {
                collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .canJoinAllApplications, .fullScreenAuxiliary]
            } else {
                collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
            }
            level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        } else {
            super.init(contentRect: rect, styleMask: [], backing: BackingStoreType(rawValue: 0)!, defer: false)
            collectionBehavior = [.stationary, .ignoresCycle, .canJoinAllSpaces]
            level = .screenSaver
            canHide = false
            isMovableByWindowBackground = true
            isReleasedWhenClosed = false
            alphaValue = 1
        }
        
        isOpaque = false
        hasShadow = false
        backgroundColor = NSColor.clear
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }
    
    func addMetalOverlay(screen: NSScreen) {
        overlay = Overlay(frame: frame, multiplyCompositing: self.fullsize)
        overlay?.screenUpdate(screen: screen)
        overlay?.autoresizingMask = [.width, .height]
        contentView = overlay
    }
    
    func screenUpdate(screen: NSScreen) {
        overlay?.screenUpdate(screen: screen)
    }
}

final class OverlayWindowController: NSWindowController, NSWindowDelegate {
    let fullsize: Bool
    public let screen: NSScreen
    
    init(screen: NSScreen, fullsize: Bool = false) {
        self.screen = screen
        self.fullsize = fullsize
        let overlayWindow = OverlayWindow(fullsize: fullsize)
        
        super.init(window: overlayWindow)
        overlayWindow.delegate = self
    }
    
    func open(rect: NSRect) {
        guard let window = self.window as? OverlayWindow else {
            return
        }
        window.setFrame(rect, display: true)
        
        if !fullsize {
            reposition(screen: screen)
        }
        
        window.orderFrontRegardless()
        window.addMetalOverlay(screen: screen)
    }
    
    func reposition(screen: NSScreen) {
        let targetPosition = getIdealPosition(screen: screen)
        window?.setFrameOrigin(targetPosition)
    }
    
    func getIdealPosition(screen: NSScreen) -> CGPoint {
        var position = screen.frame.origin
        position.x += 10
        position.y += 500
        return position
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func windowDidMove(_ notification: Notification) {
        if let window = window, let screen = window.screen {
            overlayLogger.info("Window moved to (\(window.frame.origin.x), \(window.frame.origin.y), current screen: \(screen.localizedName), expected screen: \(self.screen.localizedName)")
            if window.frame.origin != getIdealPosition(screen: self.screen) {
                reposition(screen: self.screen)
            }
        }
    }
}
