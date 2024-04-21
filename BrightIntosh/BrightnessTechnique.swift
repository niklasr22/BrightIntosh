//
//  OverlayTechnique.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 01.10.23.
//

import Foundation
import Cocoa

class BrightnessTechnique {
    fileprivate(set) var isEnabled: Bool = false
    
    func enable() {
        fatalError("Subclasses need to implement the `enable()` method.")
    }
    
    func enableScreen(screen: NSScreen) {
        fatalError("Subclasses need to implement the `enableScreen()` method.")
    }
    
    func disable() {
        fatalError("Subclasses need to implement the `disable()` method.")
    }
    
    func adjustBrightness() {
        if getXDRDisplays().count == 0 {
            self.disable()
        }
    }
    
    func screenUpdate(screens: [NSScreen]) {}
    
}

class GammaTechnique: BrightnessTechnique {
    
    private var overlayWindowControllers: [CGDirectDisplayID: OverlayWindowController] = [:]
    
    override init() {
        super.init()
    }
    
    override func enable() {
        getXDRDisplays().forEach {
            enableScreen(screen: $0)
        }
    }
    
    override func enableScreen(screen: NSScreen) {
        if let displayId = screen.displayId {
            let overlayWindowController = OverlayWindowController(screen: screen)
            overlayWindowControllers[displayId] = overlayWindowController
            isEnabled = true
            let rect = NSRect(x: screen.frame.origin.x, y: screen.frame.origin.y, width: 100, height: 100)
            overlayWindowController.open(rect: rect)
            adjustBrightness()
        }
    }
    
    override func disable() {
        isEnabled = false
        overlayWindowControllers.values.forEach { controller in
            controller.window?.close()
        }
        overlayWindowControllers.removeAll()
        resetGammaTable()
    }
    
    override func adjustBrightness() {
        super.adjustBrightness()
        overlayWindowControllers.values.forEach { controller in
            self.adjustGammaTable(screen: controller.screen)
        }
    }
    
    private func adjustGammaTable(screen: NSScreen) {
        if let displayId = screen.displayId, Settings.shared.brightintoshActive {
            resetGammaTable()
            
            let tableSize: Int = 256 // The size of the gamma table
            var redTable: [CGGammaValue] = [CGGammaValue](repeating: 0, count: tableSize)
            var greenTable: [CGGammaValue] = [CGGammaValue](repeating: 0, count: tableSize)
            var blueTable: [CGGammaValue] = [CGGammaValue](repeating: 0, count: tableSize)
            var sampleCount: UInt32 = 0
            let result = CGGetDisplayTransferByTable(displayId, UInt32(tableSize), &redTable, &greenTable, &blueTable, &sampleCount)
            
            guard result == CGError.success else {
                return
            }
            
            let gamma = Settings.shared.brightness
            
            for i in 0..<redTable.count {
                redTable[i] = redTable[i] * gamma
            }
            for i in 0..<greenTable.count {
                greenTable[i] = greenTable[i] * gamma
            }
            for i in 0..<blueTable.count {
                blueTable[i] = blueTable[i] * gamma
            }
            CGSetDisplayTransferByTable(displayId, UInt32(tableSize), &redTable, &greenTable, &blueTable)
            print("Set gamma table for display \(screen.localizedName) \(String(describing: screen.displayId))")
        }
    }
    
    private func resetGammaTable() {
        CGDisplayRestoreColorSyncSettings()
    }
}

class OverlayTechnique: BrightnessTechnique {
    
    private var overlayWindowControllers: [CGDirectDisplayID: OverlayWindowController] = [:]
    
    override init() {
        super.init()
    }
    
    override func enable() {
        getXDRDisplays().forEach {
            enableScreen(screen: $0)
        }
    }
    
    override func enableScreen(screen: NSScreen) {
        if let displayId = screen.displayId {
            let overlayWindowController = OverlayWindowController(screen: screen)
            overlayWindowControllers[displayId] = overlayWindowController
            let rect = NSRect(x: screen.frame.origin.x, y: screen.frame.origin.y, width: screen.frame.width, height: screen.frame.height)
            overlayWindowController.open(rect: rect)
            adjustBrightness()
        }
    }
    
    override func disable() {
        isEnabled = false
        overlayWindowControllers.values.forEach { controller in
            controller.close()
        }
        overlayWindowControllers.removeAll()
    }
    
    override func adjustBrightness() {
        super.adjustBrightness()
        overlayWindowControllers.values.forEach { controller in
            (controller.window as? OverlayWindow)?.overlay?.setMaxFrameRate(screen: controller.screen)
            (controller.window as? OverlayWindow)?.overlay?.setHDRBrightness(colorValue: Double(Settings.shared.brightness), screen: controller.screen)
        }
    }
    
    override func screenUpdate(screens: [NSScreen]) {
        for screen: NSScreen in screens {
            if let displayId = screen.displayId {
                if !overlayWindowControllers.keys.contains(displayId) {
                    enableScreen(screen: screen)
                } else {
                    adjustBrightness()
                }
            }
        }
        
        overlayWindowControllers = overlayWindowControllers.filter{ (displayId, controller) in
            if screens.filter({ $0.displayId == displayId }).isEmpty {
                print("Turn brightness off for \(controller.screen.localizedName)")
                controller.close()
                return false
            }
            return true
        }
    }
}
