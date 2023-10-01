//
//  OverlayTechnique.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 01.10.23.
//

import Foundation
import Cocoa

class BrightnessTechnique {
    func enable() {
        fatalError("Subclasses need to implement the `enable()` method.")
    }
    
    func disable() {
        fatalError("Subclasses need to implement the `disable()` method.")
    }
    
    func adjustBrightness() {
        guard let screen = getBuiltInScreen() else {
            self.disable()
            return
        }
    }
    
}

class GammaTechnique: BrightnessTechnique {
    
    private var overlayWindowController: OverlayWindowController
    
    override init() {
        overlayWindowController = OverlayWindowController()
        super.init()
    }
    
    override func enable() {
        if let screen = getBuiltInScreen() {
            let rect = NSRect(x: screen.visibleFrame.origin.x, y: screen.visibleFrame.origin.y, width: 1, height: 1)
            overlayWindowController.open(rect: rect, screen: screen)
            adjustBrightness()
        }
    }
    
    override func disable() {
        overlayWindowController.window?.close()
        resetGammaTable()
    }
    
    override func adjustBrightness() {
        super.adjustBrightness()
        if let screen = getBuiltInScreen() {
            self.adjustGammaTable(screen: screen)
        }
    }
    
    private func adjustGammaTable(screen: NSScreen) {
        if let displayId = screen.displayId, Settings.shared.brightintoshActive {
            resetGammaTable()
            
            let tableSize: Int = 256 // The size of the gamma table
            var redTable = [CGGammaValue](repeating: 0, count: tableSize)
            var greenTable = [CGGammaValue](repeating: 0, count: tableSize)
            var blueTable = [CGGammaValue](repeating: 0, count: tableSize)
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
        }
    }
    
    private func resetGammaTable() {
        CGDisplayRestoreColorSyncSettings()
    }
}

class OverlayTechnique: BrightnessTechnique {
    
    private var overlayWindowController: FullsizeOverlayWindowController
    
    override init() {
        guard let screen = getBuiltInScreen() else {
            fatalError("No Screen")
        }
        let rect = NSRect(x: screen.visibleFrame.origin.x, y: screen.visibleFrame.origin.y, width: screen.frame.width, height: screen.frame.height)
        overlayWindowController = FullsizeOverlayWindowController(rect: rect, screen: screen)
        super.init()
    }
    
    override func enable() {
        //if let screen = getBuiltInScreen() {
        //    let rect = NSRect(x: screen.visibleFrame.origin.x, y: screen.visibleFrame.origin.y, width: screen.visibleFrame.width, height: screen.visibleFrame.height)
            overlayWindowController.open()
            adjustBrightness()
        //}
    }
    
    override func disable() {
        overlayWindowController.window?.close()
    }
    
    override func adjustBrightness() {
        super.adjustBrightness()
        (overlayWindowController.window as? OverlayWindow)?.overlay?.setHDRBrightness(colorValue: Double(Settings.shared.brightness))
    }
}
