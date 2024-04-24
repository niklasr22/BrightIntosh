//
//  OverlayWindow.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 13.07.23.
//

import Cocoa

class OverlayWindow: NSWindow {
    
    var overlay: Overlay?
    var fullsize: Bool
    
    init(fullsize: Bool = false) {
        self.fullsize = fullsize
        let rect = NSRect(x: 0, y: 0, width: 1, height: 1)
        
        
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
            reposition()
        }
        
        window.orderFrontRegardless()
        window.addMetalOverlay(screen: screen)
    }
    
    func reposition() {
        window?.setFrameOrigin(getIdealPosition())
    }
    
    func getIdealPosition() -> CGPoint {
        var position = screen.frame.origin
        position.y += screen.frame.height - 1
        return position
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
