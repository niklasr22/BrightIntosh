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
        super.init(contentRect: rect, styleMask: [.fullSizeContentView, .borderless], backing: .buffered, defer: false)
        
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        setFrameOrigin(screen.frame.origin)
        isOpaque = false
        hasShadow = false
        backgroundColor = NSColor.clear
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .canJoinAllApplications, .fullScreenAuxiliary]
        makeKeyAndOrderFront(nil)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        
        guard let view = contentView else { return }
        
        overlay = Overlay(frame: view.bounds, screen: screen)
        overlay.autoresizingMask = [.width, .height]
        view.addSubview(overlay)
    }
    
    func screenUpdate(screen: NSScreen) {
        overlay.screenUpdate(screen: screen)
    }
    
}
