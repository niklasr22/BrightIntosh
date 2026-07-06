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
    private static let boostedBaselineThreshold: CGGammaValue = 1.1
    
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
        print("New baseline created (max value \(currentTable.maximumValue))")
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
        
        for i in 0..<newRedTable.count {
            newRedTable[i] *= factor
            newGreenTable[i] *= factor
            newBlueTable[i] *= factor
        }
        CGSetDisplayTransferByTable(displayId, GammaTable.tableSize, &newRedTable, &newGreenTable, &newBlueTable)
    }
    
    func reapplyIfLastValuesDrifted(displayId: CGDirectDisplayID, factor: Float, tolerance: CGGammaValue) -> Bool {
        guard !currentLastValuesMatch(displayId: displayId, factor: factor, tolerance: tolerance) else {
            return false
        }
        
        setTableForScreen(displayId: displayId, factor: factor)
        return true
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
    
    private func currentLastValuesMatch(displayId: CGDirectDisplayID, factor: Float, tolerance: CGGammaValue) -> Bool {
        guard let currentTable = Self.createFromCurrentGammaTable(displayId: displayId) else { return true }
        guard let redValue = redTable.last,
              let greenValue = greenTable.last,
              let blueValue = blueTable.last,
              let currentRedValue = currentTable.redTable.last,
              let currentGreenValue = currentTable.greenTable.last,
              let currentBlueValue = currentTable.blueTable.last else { return true }
        
        return abs(currentRedValue - (redValue * factor)) <= tolerance &&
            abs(currentGreenValue - (greenValue * factor)) <= tolerance &&
            abs(currentBlueValue - (blueValue * factor)) <= tolerance
    }
}

class HDRLifecycleBrightnessTechnique: BrightnessTechnique {
    fileprivate var hdrPollTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    fileprivate var hdrReadyDisplayIds: Set<CGDirectDisplayID> = []
    fileprivate var hdrCooldownEndDates: [CGDirectDisplayID: Date] = [:]
    /// Consecutive HDR engage timeouts per display; reset when HDR becomes ready.
    fileprivate var hdrConsecutiveTimeoutCount: [CGDirectDisplayID: Int] = [:]
    
    fileprivate let hdrReadyThreshold = 1.05
    fileprivate let hdrEngageTimeout: TimeInterval = 25
    fileprivate let hdrRetryCooldownSeconds = 30
    fileprivate let maxConsecutiveHDRTimeoutFailures = 3
    fileprivate let defaultPollInterval: Duration = .milliseconds(500)
    fileprivate let fastPollInterval: Duration = .milliseconds(16)
    fileprivate let fastPollDuration: TimeInterval = 30
    fileprivate let maxEdrEpsilon: CGFloat = 0.0001
    fileprivate let pendingHDRBrightnessFactor: Float = 1.12
    fileprivate var fastPollUntil: Date?
    
    fileprivate var shouldApplyPendingHDRBrightness: Bool {
        !BrightIntoshSettings.shared.waitForHDRBeforeIncreasingBrightness
    }
    
    static func brightnessFactor(screen: NSScreen, maxEdr: CGFloat) -> Float {
        let (referenceEdr, referenceBonusGamma) = getScreenRefGamma(screen)
        return 1 + referenceBonusGamma * min(Float(maxEdr) / referenceEdr, 1.0)
    }
    
    override func adjustBrightness() {
        super.adjustBrightness()
        fastPollUntil = Date().addingTimeInterval(fastPollDuration)
        if isEnabled {
            hdrReadyDisplaysDidChange()
        }
    }
    
    fileprivate func trackedHDRDisplayIds(additionalDisplayIds: Set<CGDirectDisplayID> = []) -> Set<CGDirectDisplayID> {
        additionalDisplayIds
            .union(Set(hdrPollTasks.keys))
            .union(hdrReadyDisplayIds)
            .union(Set(hdrCooldownEndDates.keys))
    }
    
    fileprivate func startPollTasksIfNeeded(screens: [NSScreen]) {
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
    
    fileprivate func tearDownHDRState(displayId: CGDirectDisplayID) {
        hdrPollTasks[displayId]?.cancel()
        hdrPollTasks.removeValue(forKey: displayId)
        hdrReadyDisplayIds.remove(displayId)
        hdrCooldownEndDates.removeValue(forKey: displayId)
        hdrConsecutiveTimeoutCount.removeValue(forKey: displayId)
    }
    
    /// Stops HDR polling while preserving retry cooldown deadlines across disable/enable toggles.
    fileprivate func resetActiveHDRState() {
        hdrPollTasks.values.forEach { $0.cancel() }
        hdrPollTasks.removeAll()
        hdrReadyDisplayIds.removeAll()
    }
    
    fileprivate func handleActiveHDRCooldown(_ displayId: CGDirectDisplayID, notify: Bool) -> Bool {
        guard let remainingSeconds = hdrCooldownRemainingSeconds(for: displayId) else { return false }
        
        if shouldApplyPendingHDRBrightness {
            applyPendingHDRBrightness(displayId: displayId)
        } else {
            closeBoostWindow(displayId)
        }
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
    
    private func hdrLifecycle(displayId: CGDirectDisplayID) async {
        while !Task.isCancelled, isEnabled {
            guard screenForDisplay(displayId) != nil else {
                hdrReadyDisplayIds.remove(displayId)
                return
            }
            let ready = await waitForHDR(displayId: displayId)
            guard ready, !Task.isCancelled, isEnabled, screenForDisplay(displayId) != nil else { return }
            
            hdrReadyDisplayIds.insert(displayId)
            hdrReadyDisplaysDidChange()
            
            await monitorHDR(displayId: displayId)
        }
    }
    
    /// Poll until HDR engages, or run cooldown and retry. Returns `false` if the task should exit.
    private func waitForHDR(displayId: CGDirectDisplayID) async -> Bool {
        var notReadySince: Date?
        
        while !Task.isCancelled, isEnabled {
            if let remainingCooldownSeconds = hdrCooldownRemainingSeconds(for: displayId) {
                guard await waitOutHDRCooldown(displayId: displayId, seconds: remainingCooldownSeconds) else {
                    return false
                }
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
                let cooldownSeconds = beginHDRRetryCooldown(displayId)
                guard await waitOutHDRCooldown(displayId: displayId, seconds: cooldownSeconds) else {
                    return false
                }
                notReadySince = nil
                continue
            }
            
            try? await Task.sleep(for: currentPollInterval())
        }
        return false
    }
    
    private func waitOutHDRCooldown(displayId: CGDirectDisplayID, seconds: Int) async -> Bool {
        closeBoostWindow(displayId)
        if shouldApplyPendingHDRBrightness {
            applyPendingHDRBrightness(displayId: displayId)
        }
        try? await Task.sleep(for: .seconds(seconds))
        guard !Task.isCancelled, isEnabled else { return false }
        endHDRRetryCooldown(displayId, notify: true)
        if let screen = screenForDisplay(displayId) {
            enableScreen(screen: screen)
        }
        return true
    }
    
    private func monitorHDR(displayId: CGDirectDisplayID) async {
        var lastMaxEdr: CGFloat?
        while !Task.isCancelled, isEnabled {
            guard let screen = screenForDisplay(displayId) else { break }
            if !hdrReady(screen) { break }
            
            let maxEdr = screen.maximumExtendedDynamicRangeColorComponentValue
            if lastMaxEdr.map({ abs($0 - maxEdr) > maxEdrEpsilon }) ?? true {
                lastMaxEdr = maxEdr
                hdrMaximumEDRDidChange(displayId: displayId, screen: screen, maxEdr: maxEdr)
            }
            try? await Task.sleep(for: currentPollInterval())
        }
        hdrReadyDisplayIds.remove(displayId)
        hdrDidStopBeingReady(displayId: displayId)
        hdrReadyDisplaysDidChange()
    }
    
    private func currentPollInterval() -> Duration {
        if let fastPollUntil, Date() < fastPollUntil {
            return fastPollInterval
        }
        return defaultPollInterval
    }
    
    fileprivate func screenForDisplay(_ displayId: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayId == displayId }
    }
    
    private func beginHDRRetryCooldown(_ displayId: CGDirectDisplayID) -> Int {
        let nextCount = (hdrConsecutiveTimeoutCount[displayId] ?? 0) + 1
        hdrConsecutiveTimeoutCount[displayId] = nextCount
        
        let cooldownSeconds = hdrRetryCooldownSeconds
        hdrCooldownEndDates[displayId] = Date().addingTimeInterval(TimeInterval(cooldownSeconds))
        NotificationCenter.default.post(
            name: .brightIntoshHDRCooldownDidBegin,
            object: nil,
            userInfo: [
                "cooldownSeconds": cooldownSeconds,
                "displayID": NSNumber(value: displayId),
            ]
        )
        
        if nextCount >= maxConsecutiveHDRTimeoutFailures {
            handlePersistentHDRFailure(displayId: displayId, timeoutCount: nextCount)
        }
        
        return cooldownSeconds
    }
    
    private func handlePersistentHDRFailure(displayId: CGDirectDisplayID, timeoutCount: Int) {
        let reason = "Display \(displayId) did not become HDR ready after \(timeoutCount) consecutive \(String(format: "%.1f", hdrEngageTimeout))s attempts."
        print("Persistent HDR failure detected: \(reason)")
        
        if BrightIntoshSettings.shared.brightintoshActive {
            BrightIntoshSettings.shared.brightintoshActive = false
        }
        
        Task { @MainActor in
            await presentBrightnessFailurePrompt(reason: reason)
        }
    }
    
    private func endHDRRetryCooldown(_ displayId: CGDirectDisplayID, notify: Bool) {
        hdrCooldownEndDates.removeValue(forKey: displayId)
        if notify {
            NotificationCenter.default.post(
                name: .brightIntoshHDRCooldownDidEnd,
                object: nil,
                userInfo: ["displayID": NSNumber(value: displayId)]
            )
        }
    }
    
    private func hdrCooldownRemainingSeconds(for displayId: CGDirectDisplayID) -> Int? {
        guard let cooldownEndDate = hdrCooldownEndDates[displayId] else { return nil }
        
        let remainingSeconds = cooldownEndDate.timeIntervalSinceNow
        guard remainingSeconds > 0 else {
            endHDRRetryCooldown(displayId, notify: true)
            return nil
        }
        
        return Int(ceil(remainingSeconds))
    }
    
    private func hdrReady(_ screen: NSScreen) -> Bool {
        Double(screen.maximumExtendedDynamicRangeColorComponentValue) > hdrReadyThreshold
    }
    
    @MainActor
    func appendHDRSupportDiagnostics(to report: inout String) {
        report += "HDR lifecycle (internal):\n"
        report += " - Technique enabled: \(isEnabled)\n"
        report += " - Premature brightness before HDR: \(shouldApplyPendingHDRBrightness)\n"
        report += " - HDR engage attempt timeout: \(String(format: "%.1f", hdrEngageTimeout))s\n"
        report += " - HDR retry cooldown duration: \(hdrRetryCooldownSeconds)s\n"
        report += " - HDR ready displays: \(hdrReadyDisplayIds.sorted())\n"
        report += " - Active HDR poll tasks: \(hdrPollTasks.keys.sorted())\n"
        
        if hdrCooldownEndDates.isEmpty {
            report += " - HDR retry cooldowns: none\n"
        } else {
            report += " - HDR retry cooldowns:\n"
            for displayId in hdrCooldownEndDates.keys.sorted() {
                let remaining = Int(ceil(hdrCooldownEndDates[displayId]!.timeIntervalSinceNow))
                let failures = hdrConsecutiveTimeoutCount[displayId] ?? 0
                report += "   · display \(displayId): \(max(0, remaining))s remaining, consecutive timeouts: \(failures)\n"
            }
        }
        
        if hdrConsecutiveTimeoutCount.isEmpty {
            report += " - Consecutive HDR timeout counts: none\n"
        } else {
            report += " - Consecutive HDR timeout counts: \(hdrConsecutiveTimeoutCount)\n"
        }
    }
    
    func closeBoostWindow(_ displayId: CGDirectDisplayID) {}
    func applyPendingHDRBrightness(displayId: CGDirectDisplayID) {}
    func hdrReadyDisplaysDidChange() {}
    func hdrMaximumEDRDidChange(displayId: CGDirectDisplayID, screen: NSScreen, maxEdr: CGFloat) {}
    func hdrDidStopBeingReady(displayId: CGDirectDisplayID) {}
}

class MultiplyingOverlayTechnique: HDRLifecycleBrightnessTechnique {
    private var overlayWindowControllers: [CGDirectDisplayID: OverlayWindowController] = [:]
    
    override func enable() {
        let shouldAnnounceActiveCooldowns = !isEnabled
        isEnabled = true
        updateScreens(screens: getXDRDisplays(), announceActiveCooldowns: shouldAnnounceActiveCooldowns)
    }
    
    override func enableScreen(screen: NSScreen) {
        guard let displayId = screen.displayId else { return }
        guard !handleActiveHDRCooldown(displayId, notify: false) else {
            closeBoostWindow(displayId)
            return
        }
        
        let overlayFactor = overlayBrightnessFactor(screen: screen)
        
        if let existing = overlayWindowControllers[displayId] {
            existing.window?.setFrame(screen.frame, display: true)
            existing.setOverlayClearColorValue(Double(overlayFactor))
            existing.updateScreen(screen: screen)
            return
        }
        
        let controller = OverlayWindowController(
            screen: screen,
            fullsize: true,
            overlayClearColorValue: Double(overlayFactor)
        )
        overlayWindowControllers[displayId] = controller
        controller.open(rect: screen.frame)
    }
    
    override func disable() {
        isEnabled = false
        resetActiveHDRState()
        overlayWindowControllers.values.forEach { $0.window?.close() }
        overlayWindowControllers.removeAll()
    }
    
    override func screenUpdate(screens: [NSScreen]) {
        updateScreens(screens: screens, announceActiveCooldowns: false)
    }
    
    private func updateScreens(screens: [NSScreen], announceActiveCooldowns: Bool) {
        let activeDisplayIds = Set(screens.compactMap { $0.displayId })
        let trackedDisplayIds = trackedHDRDisplayIds(additionalDisplayIds: Set(overlayWindowControllers.keys))
        
        for displayId in trackedDisplayIds where !activeDisplayIds.contains(displayId) {
            tearDownDisplay(displayId)
        }
        
        for screen in screens {
            guard let displayId = screen.displayId else { continue }
            if handleActiveHDRCooldown(displayId, notify: announceActiveCooldowns) { continue }
            enableScreen(screen: screen)
        }
        
        startPollTasksIfNeeded(screens: screens)
        fastPollUntil = Date().addingTimeInterval(fastPollDuration)
    }
    
    override func closeBoostWindow(_ displayId: CGDirectDisplayID) {
        overlayWindowControllers[displayId]?.window?.close()
        overlayWindowControllers.removeValue(forKey: displayId)
    }
    
    override func applyPendingHDRBrightness(displayId: CGDirectDisplayID) {
        overlayWindowControllers[displayId]?.setOverlayClearColorValue(Double(pendingHDRBrightnessFactor))
    }
    
    override func hdrReadyDisplaysDidChange() {
        updateOverlayBrightnessForReadyDisplays()
    }
    
    override func hdrMaximumEDRDidChange(displayId: CGDirectDisplayID, screen: NSScreen, maxEdr: CGFloat) {
        setOverlayBrightness(displayId: displayId, screen: screen, maxEdr: maxEdr)
    }
    
    override func hdrDidStopBeingReady(displayId: CGDirectDisplayID) {
        guard let screen = screenForDisplay(displayId) else { return }
        setOverlayBrightness(displayId: displayId, screen: screen, maxEdr: screen.maximumExtendedDynamicRangeColorComponentValue)
    }
    
    private func tearDownDisplay(_ displayId: CGDirectDisplayID) {
        tearDownHDRState(displayId: displayId)
        closeBoostWindow(displayId)
    }
    
    private func updateOverlayBrightnessForReadyDisplays() {
        for displayId in hdrReadyDisplayIds {
            guard let screen = screenForDisplay(displayId) else { continue }
            setOverlayBrightness(
                displayId: displayId,
                screen: screen,
                maxEdr: screen.maximumExtendedDynamicRangeColorComponentValue
            )
        }
    }
    
    private func setOverlayBrightness(displayId: CGDirectDisplayID, screen: NSScreen, maxEdr: CGFloat) {
        overlayWindowControllers[displayId]?.setOverlayClearColorValue(
            Double(Self.brightnessFactor(screen: screen, maxEdr: maxEdr))
        )
    }
    
    private func overlayBrightnessFactor(screen: NSScreen) -> Float {
        if let displayId = screen.displayId, hdrReadyDisplayIds.contains(displayId) {
            return Self.brightnessFactor(
                screen: screen,
                maxEdr: screen.maximumExtendedDynamicRangeColorComponentValue
            )
        }
        if !shouldApplyPendingHDRBrightness {
            return 1.0
        }
        return pendingHDRBrightnessFactor
    }
}

class GammaTechnique: HDRLifecycleBrightnessTechnique {
    private final class GammaApplicationState {
        var appliedFactor: Float = 1.0
        var targetFactor: Float?
        var fadeTask: Task<Void, Never>?
        var lastLoggedFactor: Float?
        var lastObservedMaxEdr: CGFloat?
    }
    
    private var overlayWindowControllers: [CGDirectDisplayID: OverlayWindowController] = [:]
    private var baselineGammaTables: [CGDirectDisplayID: GammaTable] = [:]
    private var gammaApplicationStates: [CGDirectDisplayID: GammaApplicationState] = [:]
    private var consecutiveGammaDriftReapplyCounts: [CGDirectDisplayID: Int] = [:]
    private var gammaIntegrityPollTask: Task<Void, Never>?
    
    private let gammaFadeDuration: TimeInterval = 0.35
    private let gammaFadeFrameInterval: Duration = .milliseconds(16)
    private let gammaFactorEpsilon: Float = 0.001
    private let gammaIntegrityPollInterval: Duration = .seconds(2)
    private let gammaTableTolerance: CGGammaValue = 0.003
    private let maxConsecutiveGammaDriftReapplications = 3
    
    override init() {
        super.init()
        CGDisplayRestoreColorSyncSettings()
    }
    
    override func enable() {
        let shouldAnnounceActiveCooldowns = !isEnabled
        isEnabled = true
        startGammaIntegrityPollIfNeeded()
        updateScreens(screens: getXDRDisplays(), announceActiveCooldowns: shouldAnnounceActiveCooldowns)
    }
    
    override func enableScreen(screen: NSScreen) {
        guard let displayId = screen.displayId else { return }
        guard !handleActiveHDRCooldown(displayId, notify: false) else {
            closeBoostWindow(displayId)
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
        resetActiveHDRState()
        stopGammaIntegrityPoll()
        resetGammaApplicationState()
        consecutiveGammaDriftReapplyCounts.removeAll()
        overlayWindowControllers.values.forEach { $0.window?.close() }
        overlayWindowControllers.removeAll()
        baselineGammaTables.forEach { $1.setTableForScreen(displayId: $0, factor: 1.0)}
        baselineGammaTables.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }
    
    override func screenUpdate(screens: [NSScreen]) {
        updateScreens(screens: screens, announceActiveCooldowns: false)
    }
    
    private func updateScreens(screens: [NSScreen], announceActiveCooldowns: Bool) {
        startGammaIntegrityPollIfNeeded()
        let activeIds = Set(screens.compactMap { $0.displayId })
        let tracked = trackedHDRDisplayIds(additionalDisplayIds: Set(overlayWindowControllers.keys))
        for id in tracked where !activeIds.contains(id) {
            tearDownDisplay(id)
        }
        
        baselineGammaTables.keys.forEach { resetGammaApplicationState(for: $0) }
        consecutiveGammaDriftReapplyCounts.removeAll()
        baselineGammaTables.forEach { $1.setTableForScreen(displayId: $0)}
        refreshBaselineGammaTables(for: screens)
        
        for screen in screens {
            guard let displayId = screen.displayId else { continue }
            if handleActiveHDRCooldown(displayId, notify: announceActiveCooldowns) { continue }
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
        tearDownHDRState(displayId: displayId)
        resetGammaApplicationState(for: displayId)
        consecutiveGammaDriftReapplyCounts.removeValue(forKey: displayId)
        baselineGammaTables[displayId]?.setTableForScreen(displayId: displayId)
        baselineGammaTables.removeValue(forKey: displayId)
        overlayWindowControllers[displayId]?.window?.close()
        overlayWindowControllers.removeValue(forKey: displayId)
    }
    
    private func applyGammaForHDRReadyDisplays() {
        for displayId in hdrReadyDisplayIds {
            guard let screen = NSScreen.screens.first(where: { $0.displayId == displayId }),
                  let gammaTable = baselineGammaTables[displayId] else { continue }
            let maxEdr = screen.maximumExtendedDynamicRangeColorComponentValue
            let state = gammaState(for: displayId)
            if let lastMaxEdr = state.lastObservedMaxEdr,
               abs(lastMaxEdr - maxEdr) <= maxEdrEpsilon,
               state.targetFactor != nil {
                continue
            }
            
            state.lastObservedMaxEdr = maxEdr
            let factor = Self.brightnessFactor(
                screen: screen,
                maxEdr: maxEdr
            )
            logGammaFactorIfNeeded(factor, displayId: displayId, maxEdr: maxEdr)
            fadeGammaFactor(displayId: displayId, gammaTable: gammaTable, targetFactor: factor)
        }
    }
    
    private func applyPendingHDRGamma(displayId: CGDirectDisplayID) {
        guard shouldApplyPendingHDRBrightness else { return }
        guard let gammaTable = baselineGammaTables[displayId] else { return }
        logGammaFactorIfNeeded(pendingHDRBrightnessFactor, displayId: displayId, maxEdr: 0)
        fadeGammaFactor(displayId: displayId, gammaTable: gammaTable, targetFactor: pendingHDRBrightnessFactor)
    }
    
    private func gammaState(for displayId: CGDirectDisplayID) -> GammaApplicationState {
        if let state = gammaApplicationStates[displayId] {
            return state
        }
        
        let state = GammaApplicationState()
        gammaApplicationStates[displayId] = state
        return state
    }
    
    private func fadeGammaFactor(
        displayId: CGDirectDisplayID,
        gammaTable: GammaTable,
        targetFactor: Float,
        removeStateWhenComplete: Bool = false
    ) {
        let state = gammaState(for: displayId)
        let previousTarget = state.targetFactor
        let targetChanged = previousTarget.map { abs($0 - targetFactor) > gammaFactorEpsilon } ?? true
        if !targetChanged, state.fadeTask != nil {
            return
        }
        
        let startFactor = state.appliedFactor
        state.targetFactor = targetFactor
        state.fadeTask?.cancel()
        
        if abs(startFactor - targetFactor) <= gammaFactorEpsilon {
            gammaTable.setTableForScreen(displayId: displayId, factor: targetFactor)
            finishGammaFade(displayId: displayId, factor: targetFactor, removeState: removeStateWhenComplete)
            return
        }
        
        state.fadeTask = Task { @MainActor in
            let startDate = Date()
            
            while !Task.isCancelled {
                let progress = min(1.0, Date().timeIntervalSince(startDate) / self.gammaFadeDuration)
                let easedProgress = progress * progress * (3.0 - 2.0 * progress)
                let nextFactor = startFactor + ((targetFactor - startFactor) * Float(easedProgress))
                
                gammaTable.setTableForScreen(displayId: displayId, factor: nextFactor)
                state.appliedFactor = nextFactor
                
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
        if removeState {
            gammaApplicationStates.removeValue(forKey: displayId)
        } else {
            let state = gammaState(for: displayId)
            state.fadeTask = nil
            state.appliedFactor = factor
            state.targetFactor = factor
        }
    }
    
    private func resetGammaApplicationState(for displayId: CGDirectDisplayID) {
        gammaApplicationStates[displayId]?.fadeTask?.cancel()
        gammaApplicationStates.removeValue(forKey: displayId)
    }
    
    private func resetGammaApplicationState() {
        gammaApplicationStates.values.forEach { $0.fadeTask?.cancel() }
        gammaApplicationStates.removeAll()
    }
    
    private func startGammaIntegrityPollIfNeeded() {
        guard gammaIntegrityPollTask == nil else { return }
        gammaIntegrityPollTask = Task { @MainActor in
            defer { self.gammaIntegrityPollTask = nil }
            
            while !Task.isCancelled, self.isEnabled {
                self.reapplyDriftedGammaTables()
                try? await Task.sleep(for: self.gammaIntegrityPollInterval)
            }
        }
    }
    
    private func stopGammaIntegrityPoll() {
        gammaIntegrityPollTask?.cancel()
        gammaIntegrityPollTask = nil
    }
    
    private func reapplyDriftedGammaTables() {
        for (displayId, gammaTable) in baselineGammaTables {
            guard screenForDisplay(displayId) != nil else {
                consecutiveGammaDriftReapplyCounts.removeValue(forKey: displayId)
                continue
            }
            guard let state = gammaApplicationStates[displayId],
                  state.fadeTask == nil,
                  let targetFactor = state.targetFactor else {
                consecutiveGammaDriftReapplyCounts.removeValue(forKey: displayId)
                continue
            }
            
            guard abs(state.appliedFactor - targetFactor) <= gammaFactorEpsilon else {
                consecutiveGammaDriftReapplyCounts.removeValue(forKey: displayId)
                continue
            }
            guard gammaTable.reapplyIfLastValuesDrifted(
                displayId: displayId,
                factor: state.appliedFactor,
                tolerance: gammaTableTolerance
            ) else {
                consecutiveGammaDriftReapplyCounts.removeValue(forKey: displayId)
                continue
            }
            
            let reapplyCount = (consecutiveGammaDriftReapplyCounts[displayId] ?? 0) + 1
            consecutiveGammaDriftReapplyCounts[displayId] = reapplyCount
            print("Gamma table drift detected for display \(displayId); reapplied factor \(state.appliedFactor) (\(reapplyCount)/\(maxConsecutiveGammaDriftReapplications))")
            
            if reapplyCount >= maxConsecutiveGammaDriftReapplications {
                handlePersistentGammaConflict(displayId: displayId)
                return
            }
        }
    }
    
    private func handlePersistentGammaConflict(displayId: CGDirectDisplayID) {
        let reason = "Display \(displayId) gamma values were repeatedly changed after BrightIntosh applied them."
        print("Persistent gamma conflict detected: \(reason); disabling increased brightness")
        consecutiveGammaDriftReapplyCounts.removeAll()
        
        if BrightIntoshSettings.shared.brightintoshActive {
            BrightIntoshSettings.shared.brightintoshActive = false
        } else {
            disable()
        }
        
        Task { @MainActor in
            await presentBrightnessFailurePrompt(reason: reason)
        }
    }
    
    private func logGammaFactorIfNeeded(_ factor: Float, displayId: CGDirectDisplayID, maxEdr: Double) {
        let state = gammaState(for: displayId)
        guard state.lastLoggedFactor != factor else { return }
        state.lastLoggedFactor = factor
        print("Gamma factor for display \(displayId): \(factor), Current Max EDR: \(maxEdr)")
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
    
    override func closeBoostWindow(_ displayId: CGDirectDisplayID) {
        overlayWindowControllers[displayId]?.window?.close()
        overlayWindowControllers.removeValue(forKey: displayId)
    }
    
    override func applyPendingHDRBrightness(displayId: CGDirectDisplayID) {
        applyPendingHDRGamma(displayId: displayId)
    }
    
    override func hdrReadyDisplaysDidChange() {
        applyGammaForHDRReadyDisplays()
    }
    
    override func hdrMaximumEDRDidChange(displayId: CGDirectDisplayID, screen: NSScreen, maxEdr: CGFloat) {
        applyGammaForHDRReadyDisplays()
    }
    
    override func hdrDidStopBeingReady(displayId: CGDirectDisplayID) {
        restoreGammaForDisplay(displayId)
    }
    
    override func appendHDRSupportDiagnostics(to report: inout String) {
        super.appendHDRSupportDiagnostics(to: &report)
        
        report += "Gamma application:\n"
        let trackedDisplayIds = trackedHDRDisplayIds(
            additionalDisplayIds: Set(overlayWindowControllers.keys).union(baselineGammaTables.keys)
        )
        guard !trackedDisplayIds.isEmpty else {
            report += " - Displays: none\n"
            return
        }
        
        for displayId in trackedDisplayIds.sorted() {
            let state = gammaApplicationStates[displayId]
            let appliedFactor = state?.appliedFactor ?? 1.0
            let targetFactor = state?.targetFactor
            let targetDescription = targetFactor.map { String(format: "%.4f", $0) } ?? "none"
            let lastObservedMaxEdr = state?.lastObservedMaxEdr
            let currentMaxEdr = screenForDisplay(displayId)?.maximumExtendedDynamicRangeColorComponentValue
            let phase = gammaApplicationPhase(displayId: displayId, targetFactor: targetFactor)
            
            report += " - display \(displayId): applied factor \(String(format: "%.4f", appliedFactor)), target factor \(targetDescription), phase: \(phase)"
            report += ", baseline captured: \(baselineGammaTables[displayId] != nil)"
            report += ", overlay open: \(overlayWindowControllers[displayId] != nil)"
            report += ", fade active: \(state?.fadeTask != nil)"
            if let currentMaxEdr {
                report += ", current max EDR: \(String(format: "%.4f", currentMaxEdr))"
            }
            if let lastObservedMaxEdr {
                report += ", last observed max EDR: \(String(format: "%.4f", lastObservedMaxEdr))"
            }
            report += "\n"
        }
    }
    
    private func gammaApplicationPhase(displayId: CGDirectDisplayID, targetFactor: Float?) -> String {
        guard let targetFactor else {
            return "idle/reset"
        }
        if abs(targetFactor - pendingHDRBrightnessFactor) <= gammaFactorEpsilon {
            return "pending HDR"
        }
        if hdrReadyDisplayIds.contains(displayId) {
            return "HDR ready"
        }
        if hdrCooldownEndDates[displayId] != nil {
            return "HDR cooldown"
        }
        return "active"
    }
}

@MainActor
final class CompatibilityGammaTechnique: BrightnessTechnique {
    
    private var overlayWindowControllers: [CGDirectDisplayID: OverlayWindowController] = [:]
    private var gammaTables: [CGDirectDisplayID: GammaTable] = [:]
    
    private var gammaFactor: Float {
        if let device = getModelIdentifier(), sdr600nitsDevices.contains(device) {
            return 1.535
        }
        return 1.59
    }
    
    override func enable() {
        getXDRDisplays().forEach {
            enableScreen(screen: $0)
        }
        print("Enabling compatibility gamma technique")
        isEnabled = true
        adjustBrightness()
    }
    
    override func enableScreen(screen: NSScreen) {
        guard let displayId = screen.displayId else { return }
        
        if gammaTables[displayId] == nil {
            gammaTables[displayId] = GammaTable.createFromCurrentGammaTable(displayId: displayId)
        }
        
        if let existing = overlayWindowControllers[displayId] {
            existing.updateScreen(screen: screen)
            return
        }
        
        let overlayWindowController = OverlayWindowController(screen: screen)
        overlayWindowControllers[displayId] = overlayWindowController
        let rect = NSRect(x: screen.frame.origin.x, y: screen.frame.origin.y, width: 1, height: 1)
        overlayWindowController.open(rect: rect)
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
        
        guard isEnabled else {
            return
        }
        
        overlayWindowControllers.values.forEach { controller in
            if let displayId = controller.screen.displayId,
               let gammaTable = gammaTables[displayId] {
                gammaTable.setTableForScreen(displayId: displayId, factor: gammaFactor)
            }
        }
    }
    
    override func screenUpdate(screens: [NSScreen]) {
        let activeDisplayIds = Set(screens.compactMap { $0.displayId })
        let deactivatedDisplayIds = overlayWindowControllers.keys.filter { !activeDisplayIds.contains($0) }
        
        deactivatedDisplayIds.forEach { displayId in
            overlayWindowControllers[displayId]?.window?.close()
            gammaTables[displayId]?.setTableForScreen(displayId: displayId)
            gammaTables.removeValue(forKey: displayId)
            overlayWindowControllers.removeValue(forKey: displayId)
        }
        
        screens.forEach { screen in
            guard let displayId = screen.displayId else { return }
            if overlayWindowControllers.keys.contains(displayId) {
                overlayWindowControllers[displayId]?.reposition(screen: screen)
            } else {
                enableScreen(screen: screen)
            }
        }
        
        adjustBrightness()
    }
    
    private func resetGammaTable() {
        CGDisplayRestoreColorSyncSettings()
        print("Reset gamma table for all displays")
    }
    
    @MainActor
    func appendSupportDiagnostics(to report: inout String) {
        report += "Compatibility gamma technique:\n"
        report += " - Technique enabled: \(isEnabled)\n"
        report += " - Fixed gamma factor: \(String(format: "%.4f", gammaFactor))\n"
        report += " - Overlay display IDs: \(overlayWindowControllers.keys.sorted())\n"
        report += " - Captured gamma table display IDs: \(gammaTables.keys.sorted())\n"
    }
}
