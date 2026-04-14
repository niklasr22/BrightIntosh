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
    static let tableSize: UInt32 = 256
    
    var redTable: [CGGammaValue] = [CGGammaValue](repeating: 0, count: Int(tableSize))
    var greenTable: [CGGammaValue] = [CGGammaValue](repeating: 0, count: Int(tableSize))
    var blueTable: [CGGammaValue] = [CGGammaValue](repeating: 0, count: Int(tableSize))
    
    private init() {}
    
    static func createFromCurrentGammaTable(displayId: CGDirectDisplayID) -> GammaTable? {
        let table = GammaTable()
        var sampleCount: UInt32 = 0
        let result = CGGetDisplayTransferByTable(displayId, tableSize, &table.redTable, &table.greenTable, &table.blueTable, &sampleCount)
        guard result == CGError.success else { return nil }
        return table
    }
    
    func setTableForScreen(displayId: CGDirectDisplayID, factor: Float = 1.0) {
        var newRedTable = redTable
        var newGreenTable = greenTable
        var newBlueTable = blueTable
        for i in 0..<redTable.count {
            newRedTable[i] *= factor
            newGreenTable[i] *= factor
            newBlueTable[i] *= factor
        }
        CGSetDisplayTransferByTable(displayId, GammaTable.tableSize, &newRedTable, &newGreenTable, &newBlueTable)
    }
}

class GammaTechnique: BrightnessTechnique {
    
    private var overlayWindowControllers: [CGDirectDisplayID: OverlayWindowController] = [:]
    private var baselineGammaTables: [CGDirectDisplayID: GammaTable] = [:]
    private var hdrPollTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    private var hdrReadyDisplayIds: Set<CGDirectDisplayID> = []
    private var displaysPendingHDRRetry: Set<CGDirectDisplayID> = []
    /// Consecutive HDR engage timeouts per display; each cooldown length is `min(max, step * count)`, reset when HDR becomes ready.
    private var hdrConsecutiveTimeoutCount: [CGDirectDisplayID: Int] = [:]
    
    private let hdrReadyThreshold = 1.05
    private let hdrEngageTimeout: TimeInterval = 2.1
    private let hdrRetryCooldownStepSeconds = 30
    private let hdrRetryCooldownMaxSeconds = 120
    private let pollInterval: Duration = .milliseconds(500)
    
    private static func edrGammaFactor(userBrightness: Float, maxEdr: CGFloat) -> Float {
        1 + (userBrightness - 1) * Float(maxEdr) / 4.0
    }
    
    override func enable() {
        isEnabled = true
        screenUpdate(screens: getXDRDisplays())
    }
    
    override func enableScreen(screen: NSScreen) {
        guard let displayId = screen.displayId else { return }
        if let existing = overlayWindowControllers[displayId] {
            existing.updateScreen(screen: screen)
            return
        }
        let controller = OverlayWindowController(screen: screen)
        overlayWindowControllers[displayId] = controller
        let rect = NSRect(x: screen.frame.origin.x, y: screen.frame.origin.y, width: 1, height: 1)
        controller.open(rect: rect)
        if baselineGammaTables[displayId] == nil, let table = GammaTable.createFromCurrentGammaTable(displayId: displayId) {
            baselineGammaTables[displayId] = table
        }
    }
    
    override func disable() {
        isEnabled = false
        hdrPollTasks.values.forEach { $0.cancel() }
        hdrPollTasks.removeAll()
        hdrReadyDisplayIds.removeAll()
        displaysPendingHDRRetry.removeAll()
        hdrConsecutiveTimeoutCount.removeAll()
        overlayWindowControllers.values.forEach { $0.window?.close() }
        overlayWindowControllers.removeAll()
        baselineGammaTables.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }
    
    override func adjustBrightness() {
        super.adjustBrightness()
        if isEnabled { applyGammaForHDRReadyDisplays() }
    }
    
    override func screenUpdate(screens: [NSScreen]) {
        let activeIds = Set(screens.compactMap { $0.displayId })
        let tracked = Set(overlayWindowControllers.keys)
            .union(Set(hdrPollTasks.keys))
            .union(hdrReadyDisplayIds)
            .union(displaysPendingHDRRetry)
        for id in tracked where !activeIds.contains(id) {
            tearDownDisplay(id)
        }
        
        CGDisplayRestoreColorSyncSettings()
        
        for screen in screens {
            guard let displayId = screen.displayId else { continue }
            if displaysPendingHDRRetry.contains(displayId) { continue }
            if let c = overlayWindowControllers[displayId] {
                c.updateScreen(screen: screen)
                adjustBrightness()
            } else {
                enableScreen(screen: screen)
            }
        }
        
        startPollTasksIfNeeded(screens: screens)
    }
    
    private func tearDownDisplay(_ displayId: CGDirectDisplayID) {
        hdrPollTasks[displayId]?.cancel()
        hdrPollTasks.removeValue(forKey: displayId)
        hdrReadyDisplayIds.remove(displayId)
        displaysPendingHDRRetry.remove(displayId)
        hdrConsecutiveTimeoutCount.removeValue(forKey: displayId)
        baselineGammaTables.removeValue(forKey: displayId)
        overlayWindowControllers[displayId]?.window?.close()
        overlayWindowControllers.removeValue(forKey: displayId)
    }
    
    private func startPollTasksIfNeeded(screens: [NSScreen]) {
        guard !screens.isEmpty else { return }
        let activeIds = Set(screens.compactMap { $0.displayId })
        for (id, task) in hdrPollTasks where !activeIds.contains(id) {
            task.cancel()
            hdrPollTasks.removeValue(forKey: id)
        }
        for screen in screens {
            guard let id = screen.displayId, hdrPollTasks[id] == nil else { continue }
            hdrPollTasks[id] = Task { @MainActor in
                defer { self.hdrPollTasks.removeValue(forKey: id) }
                await self.hdrLifecycle(displayId: id)
            }
        }
    }
    
    private func hdrLifecycle(displayId: CGDirectDisplayID) async {
        while !Task.isCancelled, isEnabled {
            guard screenForDisplay(displayId) != nil else {
                hdrReadyDisplayIds.remove(displayId)
                return
            }
            let ready = await waitForHDR(displayId: displayId)
            guard ready, !Task.isCancelled, isEnabled, screenForDisplay(displayId) != nil else { return }
            
            hdrReadyDisplayIds.insert(displayId)
            applyGammaForHDRReadyDisplays()
            
            await monitorHDR(displayId: displayId)
        }
    }
    
    /// Poll until HDR engages, or run cooldown and retry. Returns `false` if the task should exit.
    private func waitForHDR(displayId: CGDirectDisplayID) async -> Bool {
        var notReadySince: Date?
        
        while !Task.isCancelled, isEnabled {
            guard let screen = screenForDisplay(displayId) else {
                hdrReadyDisplayIds.remove(displayId)
                return false
            }
            if hdrReady(screen) {
                hdrConsecutiveTimeoutCount.removeValue(forKey: displayId)
                return true
            }
            
            let now = Date()
            if notReadySince == nil { notReadySince = now }
            
            if let start = notReadySince, now.timeIntervalSince(start) >= hdrEngageTimeout {
                let nextCount = (hdrConsecutiveTimeoutCount[displayId] ?? 0) + 1
                hdrConsecutiveTimeoutCount[displayId] = nextCount
                let cooldownSeconds = min(
                    hdrRetryCooldownMaxSeconds,
                    hdrRetryCooldownStepSeconds * nextCount
                )
                displaysPendingHDRRetry.insert(displayId)
                NotificationCenter.default.post(
                    name: .brightIntoshHDRCooldownDidBegin,
                    object: nil,
                    userInfo: [
                        "cooldownSeconds": cooldownSeconds,
                        "displayID": NSNumber(value: displayId),
                    ]
                )
                closeOverlay(displayId)
                try? await Task.sleep(for: .seconds(cooldownSeconds))
                displaysPendingHDRRetry.remove(displayId)
                NotificationCenter.default.post(
                    name: .brightIntoshHDRCooldownDidEnd,
                    object: nil,
                    userInfo: ["displayID": NSNumber(value: displayId)]
                )
                guard !Task.isCancelled, isEnabled else { return false }
                if let s = screenForDisplay(displayId) { enableScreen(screen: s) }
                notReadySince = nil
                continue
            }
            
            try? await Task.sleep(for: pollInterval)
        }
        return false
    }
    
    private func monitorHDR(displayId: CGDirectDisplayID) async {
        var lastFactor: Float?
        while !Task.isCancelled, isEnabled {
            guard let screen = screenForDisplay(displayId) else { break }
            if !hdrReady(screen) { break }
            
            let factor = Self.edrGammaFactor(
                userBrightness: BrightIntoshSettings.shared.brightness,
                maxEdr: screen.maximumExtendedDynamicRangeColorComponentValue
            )
            if lastFactor.map({ abs($0 - factor) > 0.001 }) ?? true {
                lastFactor = factor
                applyGammaForHDRReadyDisplays()
            }
            try? await Task.sleep(for: pollInterval)
        }
        hdrReadyDisplayIds.remove(displayId)
        applyGammaForHDRReadyDisplays()
    }
    
    private func applyGammaForHDRReadyDisplays() {
        for displayId in hdrReadyDisplayIds {
            guard let screen = NSScreen.screens.first(where: { $0.displayId == displayId }),
                  let gammaTable = baselineGammaTables[displayId] else { continue }
            let factor = Self.edrGammaFactor(
                userBrightness: BrightIntoshSettings.shared.brightness,
                maxEdr: screen.maximumExtendedDynamicRangeColorComponentValue
            )
            gammaTable.setTableForScreen(displayId: displayId, factor: factor)
        }
    }
    
    private func screenForDisplay(_ displayId: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayId == displayId }
    }
    
    private func closeOverlay(_ displayId: CGDirectDisplayID) {
        overlayWindowControllers[displayId]?.window?.close()
        overlayWindowControllers.removeValue(forKey: displayId)
    }
    
    private func hdrReady(_ screen: NSScreen) -> Bool {
        Double(screen.maximumExtendedDynamicRangeColorComponentValue) > hdrReadyThreshold
    }
}
