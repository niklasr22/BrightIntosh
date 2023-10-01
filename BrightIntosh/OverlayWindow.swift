//
//  OverlayWindow.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 13.07.23.
//

import Cocoa

class OverlayWindow: NSWindow {
    
    var overlay: Overlay?
    
    init(fullsize: Bool = false) {
        let rect = NSRect(x: 0, y: 0, width: 1, height: 1)
        
        if fullsize {
            super.init(contentRect: rect, styleMask: [.fullSizeContentView, .borderless], backing: .buffered, defer: false)
            if #available(macOS 13.0, *) {
                collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .canJoinAllApplications, .fullScreenAuxiliary]
            } else {
                collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
            }
        } else {
            super.init(contentRect: rect, styleMask: [], backing: BackingStoreType(rawValue: 0)!, defer: false)
            collectionBehavior = [.stationary, .ignoresCycle, .canJoinAllSpaces]
            level = .screenSaver
        }
        
        isOpaque = false
        hasShadow = false
        backgroundColor = NSColor.clear
        ignoresMouseEvents = true
        canHide = false
        isMovableByWindowBackground = true
        alphaValue = 1
        hidesOnDeactivate = false
        
        overlay = Overlay(frame: contentView!.bounds, multiplyCompositing: fullsize)
        contentView = overlay
    }
    
    func screenUpdate(screen: NSScreen) {
        overlay?.screenUpdate(screen: screen)
    }
}

class FullsizeOverlayWindow: NSWindow {
    
    var overlay: Overlay!
    
    init(rect: NSRect, screen: NSScreen) {
        super.init(contentRect: rect, styleMask: [.fullSizeContentView, .borderless], backing: .buffered, defer: false)
        
        setFrameOrigin(screen.frame.origin)
        isOpaque = false
        hasShadow = false
        backgroundColor = NSColor.clear
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        if #available(macOS 13.0, *) {
            collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .canJoinAllApplications, .fullScreenAuxiliary]
        } else {
            collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        }
        makeKeyAndOrderFront(nil)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        
        guard let view = contentView else { return }
        
        overlay = Overlay(frame: view.bounds, multiplyCompositing: true)
        overlay.screenUpdate(screen: screen)
        overlay.autoresizingMask = [.width, .height]
        view.addSubview(overlay)
    }
    
    func screenUpdate(screen: NSScreen) {
        overlay.screenUpdate(screen: screen)
    }
    
}

final class FullsizeOverlayWindowController: NSWindowController, NSWindowDelegate {
    
    init(rect: NSRect, screen: NSScreen) {
        let overlayWindow = FullsizeOverlayWindow(rect: rect, screen: screen)
        
        super.init(window: overlayWindow)
        overlayWindow.delegate = self
    }
    
    func open() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.orderFrontRegardless()
        window?.makeKey()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class OverlayWindowController: NSWindowController, NSWindowDelegate {
    let fullsize: Bool
    init(fullsize: Bool = false) {
        self.fullsize = fullsize
        let overlayWindow = OverlayWindow(fullsize: fullsize)
        
        super.init(window: overlayWindow)
        overlayWindow.delegate = self
    }
    
    func open(rect: NSRect, screen: NSScreen) {
        guard let window = self.window as? OverlayWindow else {
            return
        }
        
        window.screenUpdate(screen: screen)
        
        window.setFrame(rect, display: true)
        
        //window.overlay.setFrameSize(rect.size)
        window.overlay?.autoresizingMask = [.width, .height]
        
        if fullsize {
            window.setFrameOrigin(screen.frame.origin)
            window.orderFrontRegardless()
        } else {
            var position = screen.frame.origin
            position.y += screen.frame.height
            
            window.setFrameOrigin(position)
            window.orderFrontRegardless()
        }
        print("Try opening overlay")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
