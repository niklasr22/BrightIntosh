//
//  BrightnessTechnique.swift
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
        adjustBrightness()
        isEnabled = true
    }
    
    override func enableScreen(screen: NSScreen) {
        if let displayId = screen.displayId {
            let overlayWindowController = OverlayWindowController(screen: screen)
            overlayWindowControllers[displayId] = overlayWindowController
            let rect = NSRect(x: screen.frame.origin.x, y: screen.frame.origin.y, width: 1, height: 1)
            overlayWindowController.open(rect: rect)
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
        resetGammaTable()
        overlayWindowControllers.values.forEach { controller in
            self.adjustGammaTable(screen: controller.screen)
        }
    }
    
    private func adjustGammaTable(screen: NSScreen) {
        if let displayId = screen.displayId, Settings.shared.brightintoshActive {
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
        print("Reset gamma table for all displays")
    }
    
    override func screenUpdate(screens: [NSScreen]) {
        disable()
        usleep(500000)
        enable()
    }
}
