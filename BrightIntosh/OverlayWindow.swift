//
//  OverlayWindow.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 13.07.23.
//

import Cocoa

class OverlayWindow: NSWindow {
    
    init(rect: NSRect, screen: NSScreen) {
        super.init(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        
        setFrameOrigin(screen.frame.origin)
        isOpaque = false
        hasShadow = false
        backgroundColor = NSColor.clear
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        styleMask = [.fullSizeContentView]
        makeKeyAndOrderFront(nil)
        isReleasedWhenClosed = false
        
        guard let view = contentView else { return }
        
        let overlay = Overlay(frame: view.bounds)
        overlay.autoresizingMask = [.width, .height]
        view.addSubview(overlay)
    }
    
}
