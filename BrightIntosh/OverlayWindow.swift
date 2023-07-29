//
//  OverlayWindow.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 13.07.23.
//

import Cocoa

class OverlayWindow: NSWindow {
    
    private var overlay: Overlay!
    
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
        
        overlay = Overlay(frame: view.bounds, screen: screen)
        overlay.autoresizingMask = [.width, .height]
        view.addSubview(overlay)
    }
    
    func screenUpdate(screen: NSScreen) {
        overlay.screenUpdate(screen: screen)
    }
    
}
