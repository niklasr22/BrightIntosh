//
//  BrightnessTechnique.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 01.10.23.
//

import Foundation
import Cocoa

@MainActor
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
    private var pendingBrightnessPollTask: Task<Void, Never>?
    private let hdrReadyThreshold = 1.05
    private let overlayRecreateInterval = 8
    
    override init() {
        super.init()
    }
    
    override func enable() {
        isEnabled = true
        screenUpdate(screens: getXDRDisplays())
    }
    
    override func enableScreen(screen: NSScreen) {
        if let displayId = screen.displayId {
            if let overlayWindowController = overlayWindowControllers[displayId] {
                overlayWindowController.updateScreen(screen: screen)
                return
            }
            let overlayWindowController = OverlayWindowController(screen: screen)
            overlayWindowControllers[displayId] = overlayWindowController
            let rect = NSRect(x: screen.frame.origin.x, y: screen.frame.origin.y, width: 1, height: 1)
            overlayWindowController.open(rect: rect)
        }
    }
    
    override func disable() {
        isEnabled = false
        pendingBrightnessPollTask?.cancel()
        pendingBrightnessPollTask = nil
        overlayWindowControllers.values.forEach { controller in
            controller.window?.close()
        }
        overlayWindowControllers.removeAll()
        resetGammaTable()
    }
    
    override func adjustBrightness() {
        super.adjustBrightness()
        
        if isEnabled {
            resetGammaTable()
            let gamma = BrightIntoshSettings.shared.brightness
            overlayWindowControllers.values.forEach { controller in
                if let displayId = controller.screen.displayId,
                   let gammaTable = GammaTable.createFromCurrentGammaTable(displayId: displayId) {
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
            overlayWindowControllers.removeValue(forKey: displayId)
        }
        
        resetGammaTable()
        
        screens.forEach { screen in
            if let displayId = screen.displayId {
                if overlayWindowControllers.keys.contains(displayId) {
                    overlayWindowControllers[displayId]?.updateScreen(screen: screen)
                } else {
                    enableScreen(screen: screen)
                }
            }
        }
        
        
        pollForHDRAndAdjustBrightness(screens: screens)
    }
    
    private func pollForHDRAndAdjustBrightness(screens: [NSScreen]) {
        pendingBrightnessPollTask?.cancel()
        
        guard !screens.isEmpty else {
            return
        }
        
        pendingBrightnessPollTask = Task { @MainActor in
            for attempt in 1...80 {
                guard !Task.isCancelled, self.isEnabled else {
                    return
                }
                
                let refreshedScreens = self.refreshedScreens(matching: screens)
                let readyScreens = refreshedScreens.filter { self.isHDRReady(screen: $0) }
                
                if readyScreens.count == screens.count {
                    print("HDR ready for all screens after \(attempt) checks")
                    self.adjustBrightness()
                    return
                }
                
                if attempt % self.overlayRecreateInterval == 0 {
                    let stuckScreens = refreshedScreens.filter { !self.isHDRReady(screen: $0) }
                    if !stuckScreens.isEmpty {
                        self.rebuildOverlayWindows(for: stuckScreens)
                    }
                }
                
                if attempt == 1 || attempt % 10 == 0 {
                    let screenStates = refreshedScreens.map {
                        "(\(String(describing: $0.displayId)): \($0.maximumExtendedDynamicRangeColorComponentValue) / \($0.maximumReferenceExtendedDynamicRangeColorComponentValue))"
                    }.joined(separator: ", ")
                    print("Waiting for HDR readiness \(readyScreens.count)/\(screens.count): \(screenStates)")
                }
                
                try? await Task.sleep(for: .milliseconds(250))
            }
            
            print("HDR readiness polling timed out, skipping gamma apply")
        }
    }
    
    private func refreshedScreens(matching screens: [NSScreen]) -> [NSScreen] {
        screens.compactMap { targetScreen in
            guard let displayId = targetScreen.displayId else {
                return nil
            }
            
            return NSScreen.screens.first(where: { $0.displayId == displayId }) ?? targetScreen
        }
    }
    
    private func isHDRReady(screen: NSScreen) -> Bool {
        let maxEdrValue = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
        let maxReferenceEdrValue = Double(screen.maximumReferenceExtendedDynamicRangeColorComponentValue)
        return maxEdrValue > hdrReadyThreshold
    }
    
    private func rebuildOverlayWindows(for screens: [NSScreen]) {
        for screen in screens {
            guard let displayId = screen.displayId else {
                continue
            }
            
            print("Rebuilding HDR window for \(displayId)")
            overlayWindowControllers[displayId]?.window?.close()
            
            let overlayWindowController = OverlayWindowController(screen: screen)
            overlayWindowControllers[displayId] = overlayWindowController
            let rect = NSRect(x: screen.frame.origin.x, y: screen.frame.origin.y, width: 1, height: 1)
            overlayWindowController.open(rect: rect)
        }
    }
}
