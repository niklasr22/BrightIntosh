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
    var isEnabled: Bool = false 

    func enable(screens: [NSScreen]) {
        fatalError("Subclasses need to implement the `enable()` method.")
    }
    
    func enableScreen(screen: NSScreen) {
        fatalError("Subclasses need to implement the `enableScreen()` method.")
    }
    
    func disable() {
        fatalError("Subclasses need to implement the `disable()` method.")
    }
    
    func adjustBrightness() {}
    
    func adjustBrightnessValue() {
        adjustBrightness()
    }
    
    func screenUpdate(screens: [NSScreen]) {}
    
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
        let edrRatio = Float(maxEdr) / referenceEdr
        guard BrightIntoshSettings.shared.fineGrainedBrightnessControl else {
            return 1 + referenceBonusGamma * min(edrRatio, 1.0)
        }
        
        let userBrightness = BrightIntoshSettings.shared.brightness
        if userBrightness > 0.995 {
            return 1 + referenceBonusGamma * edrRatio
        }
        return 1 + referenceBonusGamma * min(edrRatio, userBrightness)
    }
    
    override func adjustBrightness() {
        super.adjustBrightness()
        fastPollUntil = Date().addingTimeInterval(fastPollDuration)
        if isEnabled {
            hdrReadyDisplaysDidChange()
        }
    }
    
    override func adjustBrightnessValue() {
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
    
    override func enable(screens: [NSScreen]) {
        let shouldAnnounceActiveCooldowns = !isEnabled
        isEnabled = true
        updateScreens(screens: screens, announceActiveCooldowns: shouldAnnounceActiveCooldowns)
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
