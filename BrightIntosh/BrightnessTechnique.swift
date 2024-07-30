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
    
    func adjustBrightness() {}
    
    func screenUpdate(screens: [NSScreen]) {}
    
}

class GammaTable {
    static let tableSize: UInt32 = 256 // The size of the gamma table
    
    var redTable: [CGGammaValue] = [CGGammaValue](repeating: 0, count: Int(tableSize))
    var greenTable: [CGGammaValue] = [CGGammaValue](repeating: 0, count: Int(tableSize))
    var blueTable: [CGGammaValue] = [CGGammaValue](repeating: 0, count: Int(tableSize))
    
    private init() {}
    
    static func createFromCurrentGammaTable(displayId: CGDirectDisplayID) -> GammaTable? {
        let table = GammaTable()
        
        var sampleCount: UInt32 = 0
        let result = CGGetDisplayTransferByTable(displayId, tableSize, &table.redTable, &table.greenTable, &table.blueTable, &sampleCount)
        
        guard result == CGError.success else {
            return nil
        }
        
        return table
    }
    
    func setTableForScreen(displayId: CGDirectDisplayID, factor: Float = 1.0) {
        var newRedTable: [CGGammaValue] = redTable
        var newGreenTable: [CGGammaValue] = greenTable
        var newBlueTable: [CGGammaValue] = blueTable
        
        for i in 0..<redTable.count {
            newRedTable[i] = newRedTable[i] * factor
        }
        for i in 0..<greenTable.count {
            newGreenTable[i] = newGreenTable[i] * factor
        }
        for i in 0..<blueTable.count {
            newBlueTable[i] = newBlueTable[i] * factor
        }
        CGSetDisplayTransferByTable(displayId, GammaTable.tableSize, &newRedTable, &newGreenTable, &newBlueTable)
    }
}

class GammaTechnique: BrightnessTechnique {
    
    private var overlayWindowControllers: [CGDirectDisplayID: OverlayWindowController] = [:]
    private var gammaTables: [CGDirectDisplayID: GammaTable] = [:]
    
    override init() {
        super.init()
    }
    
    override func enable() {
        getXDRDisplays().forEach {
            enableScreen(screen: $0)
        }
        print("Enabling")
        isEnabled = true
        adjustBrightness()
    }
    
    override func enableScreen(screen: NSScreen) {
        if let displayId = screen.displayId {
            if !gammaTables.keys.contains(displayId) {
                gammaTables[displayId] = GammaTable.createFromCurrentGammaTable(displayId: displayId)
            }
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
        gammaTables.removeAll()
        resetGammaTable()
    }
    
    override func adjustBrightness() {
        super.adjustBrightness()
        
        if isEnabled {
            let gamma = Settings.shared.brightness
            overlayWindowControllers.values.forEach { controller in
                if let displayId = controller.screen.displayId, let gammaTable = gammaTables[displayId] {
                    gammaTable.setTableForScreen(displayId: displayId, factor: gamma)
                }
            }
        }
    }
    
    private func resetGammaTable() {
        CGDisplayRestoreColorSyncSettings()
        print("Reset gamma table for all displays")
    }
    
    override func screenUpdate(screens: [NSScreen]) {
        let allDisplayIds = screens.map { $0.displayId }
        let toBeDeactivated = overlayWindowControllers.keys.filter { !allDisplayIds.contains($0) }
        
        toBeDeactivated.forEach { displayId in
            overlayWindowControllers[displayId]?.window?.close()
            gammaTables[displayId]?.setTableForScreen(displayId: displayId)
            gammaTables.removeValue(forKey: displayId)
            overlayWindowControllers.removeValue(forKey: displayId)
        }
        
        screens.forEach { screen in
            if let displayId = screen.displayId {
                if overlayWindowControllers.keys.contains(displayId) {
                    overlayWindowControllers[displayId]?.reposition(screen: screen)
                } else {
                    enableScreen(screen: screen)
                }
            }
        }
        
        adjustBrightness()
    }
}
