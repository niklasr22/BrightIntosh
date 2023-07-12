//
//  AppDelegate.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 12.07.23.
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var active: Bool = true

    @IBOutlet var window: NSWindow!


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard let screen = NSScreen.main else { return }
        let rect = NSRect(x: 0, y: 0, width: screen.frame.width, height: screen.frame.height)
        
        window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.hasShadow = false
        window.backgroundColor = NSColor.clear
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        window.collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.styleMask = [.fullSizeContentView]
        window.makeKeyAndOrderFront(nil)
        
        guard let view = window.contentView else { return }
        
        let overlay = Overlay(frame: view.bounds)
        overlay.autoresizingMask = [.width, .height]
        view.addSubview(overlay)
        
        // Menu bar app
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sun.max.circle", accessibilityDescription: "1")
        }
        setupMenus(active: active)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func setupMenus(active: Bool) {
        let menu = NSMenu()
        
        let title = NSMenuItem(title: "BrightIntosh", action: nil, keyEquivalent: "")
        let toggle = NSMenuItem(title: active ? "Disable" : "Activate", action: #selector(toggleBrightIntosh) , keyEquivalent: "1")
        let exit = NSMenuItem(title: "Exit", action: #selector(exitBrightIntosh) , keyEquivalent: "2")
        menu.addItem(title)
        menu.addItem(toggle)
        menu.addItem(exit)
        statusItem.menu = menu
    }
    
    @objc func toggleBrightIntosh() {
        active = !active
        setupMenus(active: active)
        window.setIsVisible(active)
    }
    
    @objc func exitBrightIntosh() {
        exit(0)
    }
}

