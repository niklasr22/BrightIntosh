//
//  SingleDisplayGammaTechnique.swift
//  BrightIntoshScreenHelper
//

import Cocoa
import Foundation
import OSLog

private let gammaLogger = Logger(
    subsystem: "BrightIntoshScreenHelper",
    category: "Gamma"
)

final class GammaTable {
    static let tableSize: UInt32 = 256
    
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
    
    func applyBrightnessFactor(_ factor: Float, displayId: CGDirectDisplayID) {
        var newRed = redTable
        var newGreen = greenTable
        var newBlue = blueTable
        for i in 0..<redTable.count {
            newRed[i] = redTable[i] * factor
        }
        for i in 0..<greenTable.count {
            newGreen[i] = greenTable[i] * factor
        }
        for i in 0..<blueTable.count {
            newBlue[i] = blueTable[i] * factor
        }
        CGSetDisplayTransferByTable(displayId, GammaTable.tableSize, &newRed, &newGreen, &newBlue)
    }
}

@MainActor
final class SingleDisplayGammaTechnique {
    
    private let targetDisplayId: CGDirectDisplayID
    private var overlayWindowController: OverlayWindowController?
    private var pendingBrightnessPollTask: Task<Void, Never>?
    private var postActivationEdrMonitorTask: Task<Void, Never>?
    private var baselineGamma: GammaTable?
    private var isEnabled = false
    private var cachedUserBrightness: Float
    /// EDR value from the last successful `adjustBrightness()` apply; used to detect post-activation EDR ramps.
    private var lastAppliedMaxEdr: CGFloat?
    
    private let hdrReadyThreshold = 1.05
    private let hdrRecoveryNudgeInterval = 12
    private let hdrPollIntervalMs: UInt64 = 1000
    private var hdrRecoveryCooldownUntil: Date?
    private let hdrCooldownAfterFailedPoll: TimeInterval = 45
    private var hdrRecoveryNudgesThisSession = 0
    private let maxHdrRecoveryNudgesPerSession = 4
    private let hdrPollIntervalSlowMs: UInt64 = 2000
    /// Time to allow after polling starts before treating HDR as “not immediately” available (overlay recycle path).
    private let hdrImmediateCheckGracePeriod: TimeInterval = 1.5
    /// If HDR is still not ready after the grace period on the first attempt, tear down the overlay and wait before recreating it.
    private let hdrWaitOverlayRecycleDelaySeconds: UInt64 = 30
    
    /// After HDR is ready and gamma is applied, keep polling EDR briefly so rising headroom can increase effective brightness.
    private let postActivationEdrMonitorDuration: TimeInterval = 60
    private let postActivationEdrPollIntervalMs: UInt64 = 500
    private let postActivationEdrResyncThreshold: CGFloat = 0.03
    
    init(displayId: CGDirectDisplayID, initialUserBrightness: Float) {
        self.targetDisplayId = displayId
        self.cachedUserBrightness = initialUserBrightness
    }
    
    func refreshUserBrightnessFromSuite() {
        guard let suite = UserDefaults(suiteName: defaultsSuiteName) else {
            return
        }
        cachedUserBrightness = suite.brightness
    }
    
    func enable() {
        isEnabled = true
        Task { @MainActor in
            await self.waitForScreenAndStart()
        }
    }
    
    private func waitForScreenAndStart() async {
        for _ in 1...60 where isEnabled {
            if let screen = NSScreen.screens.first(where: { $0.displayId == targetDisplayId }) {
                screenRefresh(anchorScreen: screen)
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        gammaLogger.info("SingleDisplayGammaTechnique: display \(self.targetDisplayId, privacy: .public) not found after waiting")
    }
    
    /// Full refresh: restore ColorSync, recapture baseline gamma for this display, update overlay, poll HDR.
    func screenRefresh(anchorScreen: NSScreen) {
        guard isEnabled else {
            return
        }
        postActivationEdrMonitorTask?.cancel()
        postActivationEdrMonitorTask = nil
        lastAppliedMaxEdr = nil
        refreshUserBrightnessFromSuite()
        CGDisplayRestoreColorSyncSettings()
        baselineGamma = GammaTable.createFromCurrentGammaTable(displayId: targetDisplayId)
        
        presentOverlay(for: anchorScreen)
        
        pollForHDRAndAdjustBrightness(anchorScreen: anchorScreen)
    }
    
    func handleDisplayConfigurationChanged() {
        guard isEnabled else {
            return
        }
        refreshUserBrightnessFromSuite()
        if let screen = NSScreen.screens.first(where: { $0.displayId == targetDisplayId }) {
            screenRefresh(anchorScreen: screen)
        } else {
            overlayWindowController?.window?.close()
            overlayWindowController = nil
            pendingBrightnessPollTask?.cancel()
            pendingBrightnessPollTask = nil
            gammaLogger.info("Screen was removed, terminating.")
            NSApplication.shared.terminate(nil)
        }
    }
    
    func adjustBrightness() {
        guard isEnabled else {
            return
        }
        refreshUserBrightnessFromSuite()
        guard let baseline = baselineGamma,
              let screen = NSScreen.screens.first(where: { $0.displayId == targetDisplayId }) else {
            return
        }
        let factor = gammaFactorCompensatedForEDR(userBrightness: cachedUserBrightness, screen: screen)
        let maxEdr = screen.maximumExtendedDynamicRangeColorComponentValue
        gammaLogger.info("Gamma display \(self.targetDisplayId, privacy: .public): maximumExtendedDynamicRangeColorComponentValue=\(maxEdr, privacy: .public) effectiveGammaFactor=\(factor, privacy: .public) (userBrightness=\(self.cachedUserBrightness, privacy: .public))")
        baseline.applyBrightnessFactor(factor, displayId: targetDisplayId)
        lastAppliedMaxEdr = maxEdr
    }
    
    private func gammaFactorCompensatedForEDR(userBrightness: Float, screen: NSScreen) -> Float {
        let maxEdr = max(Double(screen.maximumExtendedDynamicRangeColorComponentValue), 1.0)
        let effective = 1.0 + (Double(userBrightness) - 1.0) * maxEdr / 4.0
        return Float(effective)
    }
    
    func disable() {
        isEnabled = false
        pendingBrightnessPollTask?.cancel()
        pendingBrightnessPollTask = nil
        postActivationEdrMonitorTask?.cancel()
        postActivationEdrMonitorTask = nil
        lastAppliedMaxEdr = nil
        hdrRecoveryCooldownUntil = nil
        hdrRecoveryNudgesThisSession = 0
        overlayWindowController?.window?.close()
        overlayWindowController = nil
        baselineGamma = nil
        CGDisplayRestoreColorSyncSettings()
    }
    
    private func presentOverlay(for anchorScreen: NSScreen) {
        if let controller = overlayWindowController {
            controller.updateScreen(screen: anchorScreen)
        } else {
            let controller = OverlayWindowController(screen: anchorScreen)
            overlayWindowController = controller
            let rect = NSRect(x: anchorScreen.frame.origin.x + 20, y: anchorScreen.frame.origin.y - 200, width: 1, height: 1)
            controller.open(rect: rect)
        }
    }
    
    private func pollForHDRAndAdjustBrightness(anchorScreen: NSScreen) {
        pendingBrightnessPollTask?.cancel()
        let screens = [anchorScreen]
        pendingBrightnessPollTask = Task { @MainActor in
            if let until = self.hdrRecoveryCooldownUntil, Date() < until {
                let waitSeconds = max(0, until.timeIntervalSinceNow)
                gammaLogger.info("HDR recovery cooldown: waiting \(Int(ceil(waitSeconds)), privacy: .public)s before polling")
                let ns = UInt64(min(Double(UInt64.max), waitSeconds * 1_000_000_000))
                try? await Task.sleep(nanoseconds: ns)
                guard !Task.isCancelled, self.isEnabled else {
                    return
                }
                self.hdrRecoveryCooldownUntil = nil
            }
            
            self.hdrRecoveryNudgesThisSession = 0
            
            let hdrPollingStartedAt = Date()
            for attempt in 1...80 {
                guard !Task.isCancelled, self.isEnabled else {
                    return
                }
                
                let refreshed = self.refreshedScreens(matching: screens)
                let readyScreens = refreshed.filter { self.isHDRReady(screen: $0) }
                
                if readyScreens.count == screens.count {
                    gammaLogger.info("HDR ready for display \(self.targetDisplayId, privacy: .public) after \(attempt, privacy: .public) checks")
                    self.hdrRecoveryCooldownUntil = nil
                    self.hdrRecoveryNudgesThisSession = 0
                    self.adjustBrightness()
                    self.startPostActivationEdrMonitoring()
                    return
                }
                
                if attempt == 1 {
                    let elapsed = Date().timeIntervalSince(hdrPollingStartedAt)
                    if elapsed < self.hdrImmediateCheckGracePeriod {
                        let remaining = self.hdrImmediateCheckGracePeriod - elapsed
                        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                        guard !Task.isCancelled, self.isEnabled else {
                            return
                        }
                        let refreshedAfterGrace = self.refreshedScreens(matching: screens)
                        let readyAfterGrace = refreshedAfterGrace.filter { self.isHDRReady(screen: $0) }
                        if readyAfterGrace.count == screens.count {
                            gammaLogger.info("HDR ready for display \(self.targetDisplayId, privacy: .public) within grace period")
                            self.hdrRecoveryCooldownUntil = nil
                            self.hdrRecoveryNudgesThisSession = 0
                            self.adjustBrightness()
                            self.startPostActivationEdrMonitoring()
                            return
                        }
                    }
                    gammaLogger.info("HDR not ready after grace for display \(self.targetDisplayId, privacy: .public); closing overlay for \(self.hdrWaitOverlayRecycleDelaySeconds, privacy: .public)s")
                    self.overlayWindowController?.window?.close()
                    self.overlayWindowController = nil
                    try? await Task.sleep(for: .seconds(self.hdrWaitOverlayRecycleDelaySeconds))
                    guard !Task.isCancelled, self.isEnabled else {
                        return
                    }
                    guard let screen = NSScreen.screens.first(where: { $0.displayId == self.targetDisplayId }) else {
                        try? await Task.sleep(for: .milliseconds(self.hdrPollIntervalMs))
                        continue
                    }
                    self.presentOverlay(for: screen)
                }
                
                if attempt % self.hdrRecoveryNudgeInterval == 0 {
                    let stuck = refreshed.filter { !self.isHDRReady(screen: $0) }
                    if !stuck.isEmpty, self.hdrRecoveryNudgesThisSession < self.maxHdrRecoveryNudgesPerSession {
                        await self.nudgeExtendedDynamicRange(for: stuck)
                        self.hdrRecoveryNudgesThisSession += 1
                    }
                }
                
                if attempt == 1 || attempt % 10 == 0 {
                    let screenStates = refreshed.map {
                        "(\(String(describing: $0.displayId)): \($0.maximumExtendedDynamicRangeColorComponentValue))"
                    }.joined(separator: ", ")
                    gammaLogger.info("Waiting for HDR \(self.targetDisplayId, privacy: .public): \(screenStates, privacy: .public)")
                }
                
                let slowPoll = self.hdrRecoveryNudgesThisSession >= self.maxHdrRecoveryNudgesPerSession
                let sleepMs = slowPoll ? self.hdrPollIntervalSlowMs : self.hdrPollIntervalMs
                try? await Task.sleep(for: .milliseconds(sleepMs))
            }
            
            self.hdrRecoveryCooldownUntil = Date().addingTimeInterval(self.hdrCooldownAfterFailedPoll)
            gammaLogger.info("HDR polling timed out for \(self.targetDisplayId, privacy: .public); cooldown \(Int(self.hdrCooldownAfterFailedPoll), privacy: .public)s")
        }
    }
    
    private func refreshedScreens(matching screens: [NSScreen]) -> [NSScreen] {
        screens.compactMap { target in
            guard let id = target.displayId else {
                return nil
            }
            return NSScreen.screens.first(where: { $0.displayId == id }) ?? target
        }
    }
    
    private func isHDRReady(screen: NSScreen) -> Bool {
        Double(screen.maximumExtendedDynamicRangeColorComponentValue) > hdrReadyThreshold
    }
    
    private func nudgeExtendedDynamicRange(for screens: [NSScreen]) async {
        for screen in screens {
            guard screen.displayId == targetDisplayId else {
                continue
            }
            gammaLogger.info("Nudging EDR for display \(self.targetDisplayId, privacy: .public)")
            overlayWindowController?.nudgeExtendedDynamicRangeContent()
        }
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled, isEnabled else {
            return
        }
    }
    
    private func startPostActivationEdrMonitoring() {
        postActivationEdrMonitorTask?.cancel()
        postActivationEdrMonitorTask = Task { @MainActor in
            let deadline = Date().addingTimeInterval(self.postActivationEdrMonitorDuration)
            while Date() < deadline, !Task.isCancelled, self.isEnabled {
                try? await Task.sleep(for: .milliseconds(self.postActivationEdrPollIntervalMs))
                guard !Task.isCancelled, self.isEnabled else {
                    return
                }
                guard let screen = NSScreen.screens.first(where: { $0.displayId == self.targetDisplayId }),
                      let last = self.lastAppliedMaxEdr else {
                    continue
                }
                let current = screen.maximumExtendedDynamicRangeColorComponentValue
                guard current > self.hdrReadyThreshold else {
                    continue
                }
                let delta = abs(current - last)
                guard delta >= self.postActivationEdrResyncThreshold else {
                    continue
                }
                gammaLogger.info("Post-activation EDR change for display \(self.targetDisplayId, privacy: .public): \(last, privacy: .public) → \(current, privacy: .public), reapplying gamma")
                self.adjustBrightness()
            }
        }
    }
}
