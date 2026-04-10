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
    /// Restored gamma curve per display, captured once when the overlay for that display is first opened (after a full reset).
    private var baselineGammaTables: [CGDirectDisplayID: GammaTable] = [:]
    private var hdrPollTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    private var hdrReadyDisplayIds: Set<CGDirectDisplayID> = []
    /// Displays in the post-failure cooldown: overlay stays closed and `screenUpdate` must not recreate it.
    private var displaysPendingHDRRetry: Set<CGDirectDisplayID> = []
    
    private let hdrReadyThreshold = 1.05
    private let hdrNotReadyBeforeCooldown: TimeInterval = 2.0
    /// After HDR fails to engage, overlay stays closed for this long before retrying (adjust in code if needed).
    private let hdrRetryCooldownSeconds = 30
    private let hdrPollInterval: Duration = .milliseconds(250)
    private let overlayRecreatePollInterval = 8
    
    override init() {
        super.init()
    }
    
    /// Maps user brightness slider to a gamma factor using the display's current max EDR headroom (matches overlay clear color scale of 4.0).
    private static func edrAwareGammaFactor(userBrightness: Float, maxEdr: CGFloat) -> Float {
        let edr = Float(maxEdr)
        return 1 + (userBrightness - 1) * edr / 4.0
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
            captureBaselineGammaTableIfNeeded(displayId: displayId)
        }
    }
    
    private func captureBaselineGammaTableIfNeeded(displayId: CGDirectDisplayID) {
        guard baselineGammaTables[displayId] == nil else {
            return
        }
        if let table = GammaTable.createFromCurrentGammaTable(displayId: displayId) {
            baselineGammaTables[displayId] = table
        }
    }
    
    override func disable() {
        isEnabled = false
        hdrPollTasks.values.forEach { $0.cancel() }
        hdrPollTasks.removeAll()
        hdrReadyDisplayIds.removeAll()
        displaysPendingHDRRetry.removeAll()
        overlayWindowControllers.values.forEach { controller in
            controller.window?.close()
        }
        overlayWindowControllers.removeAll()
        baselineGammaTables.removeAll()
        resetGammaTable()
    }
    
    override func adjustBrightness() {
        super.adjustBrightness()
        
        if isEnabled {
            applyGammaForHDRReadyDisplays()
        }
    }
    
    private func applyGammaForHDRReadyDisplays() {
        for displayId in hdrReadyDisplayIds {
            guard let screen = NSScreen.screens.first(where: { $0.displayId == displayId }),
                  let gammaTable = baselineGammaTables[displayId] else {
                continue
            }
            let factor = Self.edrAwareGammaFactor(
                userBrightness: BrightIntoshSettings.shared.brightness,
                maxEdr: screen.maximumExtendedDynamicRangeColorComponentValue
            )
            gammaTable.setTableForScreen(displayId: displayId, factor: factor)
        }
    }
    
    private func resetGammaTable() {
        CGDisplayRestoreColorSyncSettings()
        print("Reset gamma table for all displays")
    }
    
    override func screenUpdate(screens: [NSScreen]) {
        let activeDisplayIds = Set(screens.compactMap { $0.displayId })
        let trackedDisplayIds = Set(overlayWindowControllers.keys)
            .union(Set(hdrPollTasks.keys))
            .union(hdrReadyDisplayIds)
            .union(displaysPendingHDRRetry)
        let toBeDeactivated = trackedDisplayIds.filter { !activeDisplayIds.contains($0) }
        
        toBeDeactivated.forEach { displayId in
            hdrPollTasks[displayId]?.cancel()
            hdrPollTasks.removeValue(forKey: displayId)
            hdrReadyDisplayIds.remove(displayId)
            displaysPendingHDRRetry.remove(displayId)
            baselineGammaTables.removeValue(forKey: displayId)
            overlayWindowControllers[displayId]?.window?.close()
            overlayWindowControllers.removeValue(forKey: displayId)
        }
        
        resetGammaTable()
        
        screens.forEach { screen in
            if let displayId = screen.displayId {
                if displaysPendingHDRRetry.contains(displayId) {
                    return
                }
                if overlayWindowControllers.keys.contains(displayId) {
                    overlayWindowControllers[displayId]?.updateScreen(screen: screen)
                } else {
                    enableScreen(screen: screen)
                }
            }
        }
        
        syncHDRPollTasks(with: screens)
    }
    
    private func syncHDRPollTasks(with screens: [NSScreen]) {
        let activeIds = Set(screens.compactMap { $0.displayId })
        
        for (displayId, task) in hdrPollTasks where !activeIds.contains(displayId) {
            task.cancel()
            hdrPollTasks.removeValue(forKey: displayId)
        }
        
        guard !screens.isEmpty else {
            return
        }
        
        for screen in screens {
            guard let displayId = screen.displayId else {
                continue
            }
            if hdrPollTasks[displayId] != nil {
                continue
            }
            hdrPollTasks[displayId] = Task { @MainActor in
                defer { self.hdrPollTasks.removeValue(forKey: displayId) }
                await self.hdrLifecycle(for: displayId)
            }
        }
    }
    
    private func hdrLifecycle(for displayId: CGDirectDisplayID) async {
        let poll = hdrPollInterval
        var pollCount = 0
        
        while !Task.isCancelled, isEnabled {
            guard screenForDisplay(displayId) != nil else {
                hdrReadyDisplayIds.remove(displayId)
                return
            }
            
            pollCount = 0
            var notReadySince: Date?
            
            waitLoop: while !Task.isCancelled, isEnabled {
                guard let screen = screenForDisplay(displayId) else {
                    hdrReadyDisplayIds.remove(displayId)
                    return
                }
                
                if isHDRReady(screen: screen) {
                    break waitLoop
                }
                
                let now = Date()
                if notReadySince == nil {
                    notReadySince = now
                }
                
                pollCount += 1
                if pollCount % overlayRecreatePollInterval == 0 {
                    rebuildOverlayWindows(for: [screen])
                }
                
                if let start = notReadySince, now.timeIntervalSince(start) >= hdrNotReadyBeforeCooldown {
                    print("HDR not ready for display \(displayId) for \(hdrNotReadyBeforeCooldown)s; closing overlay for \(hdrRetryCooldownSeconds)s cooldown")
                    displaysPendingHDRRetry.insert(displayId)
                    closeOverlayForDisplay(displayId)
                    try? await Task.sleep(for: .seconds(hdrRetryCooldownSeconds))
                    displaysPendingHDRRetry.remove(displayId)
                    guard !Task.isCancelled, isEnabled else {
                        return
                    }
                    if let s = screenForDisplay(displayId) {
                        enableScreen(screen: s)
                    }
                    pollCount = 0
                    notReadySince = nil
                    continue waitLoop
                }
                
                try? await Task.sleep(for: poll)
            }
            
            guard !Task.isCancelled, isEnabled, screenForDisplay(displayId) != nil else {
                return
            }
            
            hdrReadyDisplayIds.insert(displayId)
            applyGammaForHDRReadyDisplays()
            print("HDR ready for display \(displayId)")
            
            var lastFactor: Float?
            while !Task.isCancelled, isEnabled {
                guard let screen = screenForDisplay(displayId) else {
                    hdrReadyDisplayIds.remove(displayId)
                    applyGammaForHDRReadyDisplays()
                    break
                }
                if !isHDRReady(screen: screen) {
                    hdrReadyDisplayIds.remove(displayId)
                    applyGammaForHDRReadyDisplays()
                    break
                }
                let factor = Self.edrAwareGammaFactor(
                    userBrightness: BrightIntoshSettings.shared.brightness,
                    maxEdr: screen.maximumExtendedDynamicRangeColorComponentValue
                )
                let shouldApply = lastFactor.map { abs($0 - factor) > 0.001 } ?? true
                if shouldApply {
                    lastFactor = factor
                    applyGammaForHDRReadyDisplays()
                }
                try? await Task.sleep(for: poll)
            }
        }
    }
    
    private func screenForDisplay(_ displayId: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayId == displayId }
    }
    
    private func closeOverlayForDisplay(_ displayId: CGDirectDisplayID) {
        overlayWindowControllers[displayId]?.window?.close()
        overlayWindowControllers.removeValue(forKey: displayId)
    }
    
    private func isHDRReady(screen: NSScreen) -> Bool {
        Double(screen.maximumExtendedDynamicRangeColorComponentValue) > hdrReadyThreshold
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
