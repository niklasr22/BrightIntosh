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
    var overlayClearColorValue: Double
    
    init(fullsize: Bool = false, overlayClearColorValue: Double = 1.6) {
        self.fullsize = fullsize
        self.overlayClearColorValue = overlayClearColorValue
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
        
        animationBehavior = .none
        isOpaque = false
        hasShadow = false
        backgroundColor = NSColor.clear
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }
    
    func addMetalOverlay(screen: NSScreen, onFirstFrameRendered: (() -> Void)? = nil) {
        installMetalOverlay(screen: screen, onFirstFrameRendered: onFirstFrameRendered)
    }
    
    func screenUpdate(screen: NSScreen) {
        overlay?.screenUpdate(screen: screen)
    }
    
    func setOverlayClearColorValue(_ value: Double) {
        overlayClearColorValue = value
        overlay?.setClearColorValue(value)
    }
    
    private func installMetalOverlay(screen: NSScreen, onFirstFrameRendered: (() -> Void)?) {
        overlay = Overlay(
            frame: NSRect(origin: .zero, size: frame.size),
            multiplyCompositing: self.fullsize,
            clearColorValue: overlayClearColorValue
        )
        overlay?.onFirstFrameRendered = onFirstFrameRendered
        overlay?.screenUpdate(screen: screen)
        overlay?.autoresizingMask = [.width, .height]
        contentView = overlay
    }
}

final class OverlayWindowController: NSWindowController, NSWindowDelegate {
    
    let fullsize: Bool
    public private(set) var screen: NSScreen
    
    init(screen: NSScreen, fullsize: Bool = false, overlayClearColorValue: Double = 1.6) {
        self.screen = screen
        self.fullsize = fullsize
        let overlayWindow = OverlayWindow(fullsize: fullsize, overlayClearColorValue: overlayClearColorValue)
        overlayWindow.title = "BrightIntosh Overlay \(String(describing: screen.displayId))"
        
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
        
        if fullsize {
            window.alphaValue = 0
        }
        
        window.addMetalOverlay(screen: screen) { [weak window] in
            window?.alphaValue = 1
        }
        window.displayIfNeeded()
        window.orderFrontRegardless()
        window.overlay?.draw()
        
        if fullsize {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak window] in
                window?.alphaValue = 1
            }
        }
    }
    
    func updateScreen(screen: NSScreen) {
        self.screen = screen
        
        guard let window = self.window as? OverlayWindow else {
            return
        }
                
        window.screenUpdate(screen: screen)
        window.orderFrontRegardless()
        
        if !fullsize {
            reposition(screen: screen)
        }
    }
    
    func setOverlayClearColorValue(_ value: Double) {
        guard let window = self.window as? OverlayWindow else {
            return
        }
        window.setOverlayClearColorValue(value)
    }
    
    func reposition(screen: NSScreen) {
        let targetPosition = getIdealPosition(screen: screen)
        window?.setFrameOrigin(targetPosition)
    }
    
    func getIdealPosition(screen: NSScreen) -> CGPoint {
        var position = screen.frame.origin
        position.y += screen.frame.height - 1
        return position
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func windowDidMove(_ notification: Notification) {
        guard !fullsize else { return }
        
        if let window = window, let screen = window.screen {
            overlayLogger.info("Window moved to (\(window.frame.origin.x), \(window.frame.origin.y), current screen: \(screen.localizedName), expected screen: \(self.screen.localizedName)")
            if window.frame.origin != getIdealPosition(screen: self.screen) {
                reposition(screen: self.screen)
            }
        }
    }
}
