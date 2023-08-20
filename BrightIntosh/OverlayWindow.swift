//
//  OverlayWindow.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 13.07.23.
//

import Cocoa

class OverlayWindow: NSWindow {
    
    private var overlay: Overlay?
    
    init(rect: NSRect, screen: NSScreen) {
        super.init(contentRect: rect, styleMask: [], backing: BackingStoreType(rawValue: 0)!, defer: false)
        
        var position = screen.frame.origin
        position.y += screen.frame.height
        
        setFrameOrigin(position)
        isOpaque = false
        hasShadow = false
        backgroundColor = NSColor.clear
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.stationary, .ignoresCycle, .canJoinAllSpaces]
        isReleasedWhenClosed = false
        canHide = false
        isMovableByWindowBackground = true
        alphaValue = 1
        orderFrontRegardless()
        
        overlay = Overlay(frame: rect, screen: screen)
        contentView = overlay
    }
    
    func screenUpdate(screen: NSScreen) {
        overlay?.screenUpdate(screen: screen)
    }
    
}
