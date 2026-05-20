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
    private static let boostedBaselineThreshold: CGGammaValue = 1.2
    
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
    
    static func createCleanBaseline(displayId: CGDirectDisplayID) -> GammaTable? {
        guard let currentTable = createFromCurrentGammaTable(displayId: displayId) else { return nil }
        guard currentTable.appearsBoosted else { return currentTable }
        
        print("Detected boosted gamma baseline with max value \(currentTable.maximumValue); restoring ColorSync settings")
        CGDisplayRestoreColorSyncSettings()
        
        guard let restoredTable = createFromCurrentGammaTable(displayId: displayId) else {
            return currentTable.normalizedByMaximum()
        }
        guard restoredTable.appearsBoosted else { return restoredTable }
        
        print("Restored gamma baseline still looks boosted with max value \(restoredTable.maximumValue); normalizing captured table")
        return restoredTable.normalizedByMaximum()
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
    
    private var maximumValue: CGGammaValue {
        max(redTable.max() ?? 0, greenTable.max() ?? 0, blueTable.max() ?? 0)
    }
    
    private var appearsBoosted: Bool {
        maximumValue > Self.boostedBaselineThreshold
    }
    
    private func normalizedByMaximum() -> GammaTable? {
        let maxValue = maximumValue
        guard maxValue > 0 else { return nil }
        
        let table = GammaTable()
        table.redTable = redTable.map { $0 / maxValue }
        table.greenTable = greenTable.map { $0 / maxValue }
        table.blueTable = blueTable.map { $0 / maxValue }
        return table
    }
}

class GammaTechnique: BrightnessTechnique {
    
    private var overlayWindowControllers: [CGDirectDisplayID: OverlayWindowController] = [:]
    private var baselineGammaTables: [CGDirectDisplayID: GammaTable] = [:]
    private var hdrPollTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    private var hdrReadyDisplayIds: Set<CGDirectDisplayID> = []
    private var displaysPendingHDRRetry: Set<CGDirectDisplayID> = []
    private var hdrRetryCooldownEndDates: [CGDirectDisplayID: Date] = [:]
    /// Consecutive HDR engage timeouts per display; each cooldown length is `min(max, step * count)`, reset when HDR becomes ready.
    private var hdrConsecutiveTimeoutCount: [CGDirectDisplayID: Int] = [:]
    private var lastLoggedGammaFactors: [CGDirectDisplayID: Float] = [:]
    private var appliedGammaFactors: [CGDirectDisplayID: Float] = [:]
    private var targetGammaFactors: [CGDirectDisplayID: Float] = [:]
    private var gammaFadeTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    
    private let hdrReadyThreshold = 1.05
    private let hdrEngageTimeout: TimeInterval = 2.1
    private let hdrRetryCooldownStepSeconds = 30
    private let hdrRetryCooldownMaxSeconds = 120
    private let defaultPollInterval: Duration = .milliseconds(500)
    private let fastPollInterval: Duration = .milliseconds(16)
    private let fastPollDuration: TimeInterval = 30
    private let gammaFadeDuration: TimeInterval = 0.35
    private let gammaFadeFrameInterval: Duration = .milliseconds(16)
    private let gammaFactorEpsilon: Float = 0.001
    private var fastPollUntil: Date?
    
    override init() {
        super.init()
        CGDisplayRestoreColorSyncSettings()
    }
    
    private static func edrGammaFactor(screen: NSScreen) -> Float {
        let referenceEdr: Float = 4.0 // This value is some empirically determined value that macOS usually allows.
        let maxEdr = screen.maximumExtendedDynamicRangeColorComponentValue
        let maxScreenBrightness = getScreenRefGamma(screen)
        let val =  1 + (maxScreenBrightness - 1) * min(Float(maxEdr) / referenceEdr, 1.0)
        return val
    }
    
    override func enable() {
        let shouldAnnounceActiveCooldowns = !isEnabled
        isEnabled = true
        updateScreens(screens: getXDRDisplays(), announceActiveCooldowns: shouldAnnounceActiveCooldowns)
    }
    
    override func enableScreen(screen: NSScreen) {
        guard let displayId = screen.displayId else { return }
        guard !isInHDRRetryCooldown(displayId, notify: false) else {
            closeOverlay(displayId)
            return
        }
        if let existing = overlayWindowControllers[displayId] {
            existing.updateScreen(screen: screen)
            return
        }
        captureBaselineGammaTableIfNeeded(displayId: displayId)
        let controller = OverlayWindowController(screen: screen)
        overlayWindowControllers[displayId] = controller
        let rect = NSRect(x: screen.frame.origin.x, y: screen.frame.origin.y, width: 1, height: 1)
        controller.open(rect: rect)
    }
    
    override func disable() {
        isEnabled = false
        hdrPollTasks.values.forEach { $0.cancel() }
        hdrPollTasks.removeAll()
        hdrReadyDisplayIds.removeAll()
        lastLoggedGammaFactors.removeAll()
        resetGammaFadeState()
        overlayWindowControllers.values.forEach { $0.window?.close() }
        overlayWindowControllers.removeAll()
        baselineGammaTables.forEach { $1.setTableForScreen(displayId: $0, factor: 1.0)}
        baselineGammaTables.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }
    
    override func adjustBrightness() {
        super.adjustBrightness()
        fastPollUntil = Date().addingTimeInterval(fastPollDuration)
        if isEnabled { applyGammaForHDRReadyDisplays() }
    }
    
    override func screenUpdate(screens: [NSScreen]) {
        updateScreens(screens: screens, announceActiveCooldowns: false)
    }
    
    private func updateScreens(screens: [NSScreen], announceActiveCooldowns: Bool) {
        let activeIds = Set(screens.compactMap { $0.displayId })
        let tracked = Set(overlayWindowControllers.keys)
            .union(Set(hdrPollTasks.keys))
            .union(hdrReadyDisplayIds)
            .union(displaysPendingHDRRetry)
            .union(Set(hdrRetryCooldownEndDates.keys))
        for id in tracked where !activeIds.contains(id) {
            tearDownDisplay(id)
        }
        
        baselineGammaTables.keys.forEach { resetGammaFadeState(for: $0) }
        baselineGammaTables.forEach { $1.setTableForScreen(displayId: $0)}
        refreshBaselineGammaTables(for: screens)
        
        for screen in screens {
            guard let displayId = screen.displayId else { continue }
            if isInHDRRetryCooldown(displayId, notify: announceActiveCooldowns) { continue }
            if let c = overlayWindowControllers[displayId] {
                c.updateScreen(screen: screen)
                adjustBrightness()
            } else {
                enableScreen(screen: screen)
            }
        }
        
        startPollTasksIfNeeded(screens: screens)
        fastPollUntil = Date().addingTimeInterval(fastPollDuration)
    }
    
    private func tearDownDisplay(_ displayId: CGDirectDisplayID) {
        hdrPollTasks[displayId]?.cancel()
        hdrPollTasks.removeValue(forKey: displayId)
        hdrReadyDisplayIds.remove(displayId)
        displaysPendingHDRRetry.remove(displayId)
        hdrRetryCooldownEndDates.removeValue(forKey: displayId)
        hdrConsecutiveTimeoutCount.removeValue(forKey: displayId)
        lastLoggedGammaFactors.removeValue(forKey: displayId)
        resetGammaFadeState(for: displayId)
        baselineGammaTables[displayId]?.setTableForScreen(displayId: displayId)
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
            if let remainingCooldownSeconds = hdrRetryCooldownRemainingSeconds(for: displayId) {
                closeOverlay(displayId)
                try? await Task.sleep(for: .seconds(remainingCooldownSeconds))
                guard !Task.isCancelled, isEnabled else { return false }
                endHDRRetryCooldown(displayId, notify: true)
                if let screen = screenForDisplay(displayId) { enableScreen(screen: screen) }
                notReadySince = nil
                continue
            }
            
            guard let screen = screenForDisplay(displayId) else {
                hdrReadyDisplayIds.remove(displayId)
                return false
            }
            if hdrReady(screen) {
                hdrConsecutiveTimeoutCount.removeValue(forKey: displayId)
                endHDRRetryCooldown(displayId, notify: false)
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
                beginHDRRetryCooldown(displayId, cooldownSeconds: cooldownSeconds)
                closeOverlay(displayId)
                try? await Task.sleep(for: .seconds(cooldownSeconds))
                guard !Task.isCancelled, isEnabled else { return false }
                endHDRRetryCooldown(displayId, notify: true)
                if let s = screenForDisplay(displayId) { enableScreen(screen: s) }
                notReadySince = nil
                continue
            }
            
            try? await Task.sleep(for: currentPollInterval())
        }
        return false
    }
    
    private func monitorHDR(displayId: CGDirectDisplayID) async {
        var lastFactor: Float?
        while !Task.isCancelled, isEnabled {
            guard let screen = screenForDisplay(displayId) else { break }
            if !hdrReady(screen) { break }
            
            let factor = Self.edrGammaFactor(
                screen: screen
            )
            if lastFactor.map({ abs($0 - factor) > 0.001 }) ?? true {
                lastFactor = factor
                applyGammaForHDRReadyDisplays()
            }
            try? await Task.sleep(for: currentPollInterval())
        }
        hdrReadyDisplayIds.remove(displayId)
        restoreGammaForDisplay(displayId)
        applyGammaForHDRReadyDisplays()
    }
    
    private func currentPollInterval() -> Duration {
        if let fastPollUntil, Date() < fastPollUntil {
            return fastPollInterval
        }
        return defaultPollInterval
    }
    
    private func applyGammaForHDRReadyDisplays() {
        for displayId in hdrReadyDisplayIds {
            guard let screen = NSScreen.screens.first(where: { $0.displayId == displayId }),
                  let gammaTable = baselineGammaTables[displayId] else { continue }
            let factor = Self.edrGammaFactor(
                screen: screen
            )
            logGammaFactorIfNeeded(factor, displayId: displayId)
            fadeGammaFactor(displayId: displayId, gammaTable: gammaTable, targetFactor: factor)
        }
    }
    
    private func fadeGammaFactor(
        displayId: CGDirectDisplayID,
        gammaTable: GammaTable,
        targetFactor: Float,
        removeStateWhenComplete: Bool = false
    ) {
        let previousTarget = targetGammaFactors[displayId]
        let targetChanged = previousTarget.map { abs($0 - targetFactor) > gammaFactorEpsilon } ?? true
        if !targetChanged, gammaFadeTasks[displayId] != nil {
            return
        }
        
        let startFactor = appliedGammaFactors[displayId] ?? 1.0
        targetGammaFactors[displayId] = targetFactor
        gammaFadeTasks[displayId]?.cancel()
        
        if abs(startFactor - targetFactor) <= gammaFactorEpsilon {
            gammaTable.setTableForScreen(displayId: displayId, factor: targetFactor)
            finishGammaFade(displayId: displayId, factor: targetFactor, removeState: removeStateWhenComplete)
            return
        }
        
        gammaFadeTasks[displayId] = Task { @MainActor in
            let startDate = Date()
            
            while !Task.isCancelled {
                let progress = min(1.0, Date().timeIntervalSince(startDate) / self.gammaFadeDuration)
                let easedProgress = progress * progress * (3.0 - 2.0 * progress)
                let nextFactor = startFactor + ((targetFactor - startFactor) * Float(easedProgress))
                
                gammaTable.setTableForScreen(displayId: displayId, factor: nextFactor)
                self.appliedGammaFactors[displayId] = nextFactor
                
                if progress >= 1.0 {
                    break
                }
                
                try? await Task.sleep(for: self.gammaFadeFrameInterval)
            }
            
            guard !Task.isCancelled else {
                return
            }
            
            gammaTable.setTableForScreen(displayId: displayId, factor: targetFactor)
            self.finishGammaFade(displayId: displayId, factor: targetFactor, removeState: removeStateWhenComplete)
        }
    }
    
    private func finishGammaFade(displayId: CGDirectDisplayID, factor: Float, removeState: Bool) {
        gammaFadeTasks.removeValue(forKey: displayId)
        
        if removeState {
            appliedGammaFactors.removeValue(forKey: displayId)
            targetGammaFactors.removeValue(forKey: displayId)
        } else {
            appliedGammaFactors[displayId] = factor
            targetGammaFactors[displayId] = factor
        }
    }
    
    private func resetGammaFadeState(for displayId: CGDirectDisplayID) {
        gammaFadeTasks[displayId]?.cancel()
        gammaFadeTasks.removeValue(forKey: displayId)
        appliedGammaFactors.removeValue(forKey: displayId)
        targetGammaFactors.removeValue(forKey: displayId)
    }
    
    private func resetGammaFadeState() {
        gammaFadeTasks.values.forEach { $0.cancel() }
        gammaFadeTasks.removeAll()
        appliedGammaFactors.removeAll()
        targetGammaFactors.removeAll()
    }
    
    private func logGammaFactorIfNeeded(_ factor: Float, displayId: CGDirectDisplayID) {
        guard lastLoggedGammaFactors[displayId] != factor else { return }
        lastLoggedGammaFactors[displayId] = factor
        print("Gamma factor for display \(displayId): \(factor)")
    }
    
    private func captureBaselineGammaTableIfNeeded(displayId: CGDirectDisplayID) {
        guard baselineGammaTables[displayId] == nil else { return }
        
        CGDisplayRestoreColorSyncSettings()
        if let table = GammaTable.createCleanBaseline(displayId: displayId) {
            baselineGammaTables[displayId] = table
        }
        applyGammaForHDRReadyDisplays()
    }
    
    private func refreshBaselineGammaTables(for screens: [NSScreen]) {
        CGDisplayRestoreColorSyncSettings()
        for screen in screens {
            guard let displayId = screen.displayId,
                  let table = GammaTable.createCleanBaseline(displayId: displayId) else { continue }
            baselineGammaTables[displayId] = table
        }
    }
    
    private func restoreGammaForDisplay(_ displayId: CGDirectDisplayID) {
        guard let gammaTable = baselineGammaTables[displayId] else {
            CGDisplayRestoreColorSyncSettings()
            applyGammaForHDRReadyDisplays()
            return
        }
        fadeGammaFactor(
            displayId: displayId,
            gammaTable: gammaTable,
            targetFactor: 1.0,
            removeStateWhenComplete: true
        )
    }
    
    private func screenForDisplay(_ displayId: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayId == displayId }
    }
    
    private func closeOverlay(_ displayId: CGDirectDisplayID) {
        overlayWindowControllers[displayId]?.window?.close()
        overlayWindowControllers.removeValue(forKey: displayId)
    }
    
    private func beginHDRRetryCooldown(_ displayId: CGDirectDisplayID, cooldownSeconds: Int) {
        displaysPendingHDRRetry.insert(displayId)
        hdrRetryCooldownEndDates[displayId] = Date().addingTimeInterval(TimeInterval(cooldownSeconds))
        NotificationCenter.default.post(
            name: .brightIntoshHDRCooldownDidBegin,
            object: nil,
            userInfo: [
                "cooldownSeconds": cooldownSeconds,
                "displayID": NSNumber(value: displayId),
            ]
        )
    }
    
    private func endHDRRetryCooldown(_ displayId: CGDirectDisplayID, notify: Bool) {
        displaysPendingHDRRetry.remove(displayId)
        hdrRetryCooldownEndDates.removeValue(forKey: displayId)
        if notify {
            NotificationCenter.default.post(
                name: .brightIntoshHDRCooldownDidEnd,
                object: nil,
                userInfo: ["displayID": NSNumber(value: displayId)]
            )
        }
    }
    
    private func isInHDRRetryCooldown(_ displayId: CGDirectDisplayID, notify: Bool) -> Bool {
        guard let remainingSeconds = hdrRetryCooldownRemainingSeconds(for: displayId) else { return false }
        
        displaysPendingHDRRetry.insert(displayId)
        if notify {
            NotificationCenter.default.post(
                name: .brightIntoshHDRCooldownDidBegin,
                object: nil,
                userInfo: [
                    "cooldownSeconds": remainingSeconds,
                    "displayID": NSNumber(value: displayId),
                ]
            )
        }
        return true
    }
    
    private func hdrRetryCooldownRemainingSeconds(for displayId: CGDirectDisplayID) -> Int? {
        guard let cooldownEndDate = hdrRetryCooldownEndDates[displayId] else {
            displaysPendingHDRRetry.remove(displayId)
            return nil
        }
        
        let remainingSeconds = cooldownEndDate.timeIntervalSinceNow
        guard remainingSeconds > 0 else {
            endHDRRetryCooldown(displayId, notify: true)
            return nil
        }
        
        displaysPendingHDRRetry.insert(displayId)
        return Int(ceil(remainingSeconds))
    }
    
    private func hdrReady(_ screen: NSScreen) -> Bool {
        Double(screen.maximumExtendedDynamicRangeColorComponentValue) > hdrReadyThreshold
    }
}
