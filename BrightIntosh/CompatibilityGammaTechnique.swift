//
//  CompatibilityGammaTechnique.swift
//  BrightIntosh
//

import Cocoa
import CoreGraphics

@MainActor
final class CompatibilityGammaTechnique: BrightnessTechnique {
    private final class FadeState {
        var appliedFactor: Float = 1.0
        var targetFactor: Float?
        var task: Task<Void, Never>?
    }

    private var overlayWindowControllers: [CGDirectDisplayID: OverlayWindowController] = [:]
    private var gammaTables: [CGDirectDisplayID: GammaTable] = [:]
    private var fadeStates: [CGDirectDisplayID: FadeState] = [:]
    private var hdrReadyDisplayIds: Set<CGDirectDisplayID> = []
    private var consecutiveRecoveryCounts: [CGDirectDisplayID: Int] = [:]
    private var integrityPollTask: Task<Void, Never>?

    nonisolated private static let colorStateLock = NSLock()
    private let gammaFadeDuration: TimeInterval = 0.2
    private let gammaFadeFrameInterval: Duration = .milliseconds(16)
    private let gammaFactorEpsilon: Float = 0.001
    private let integrityPollInterval: Duration = .seconds(2)
    private let gammaTableTolerance: CGGammaValue = 0.003
    private let hdrReadyThreshold: CGFloat = 1.05
    private let maxConsecutiveRecoveryAttempts = 3

    nonisolated static func restoreSystemColorState() {
        colorStateLock.lock()
        defer { colorStateLock.unlock() }
        CGDisplayRestoreColorSyncSettings()
    }

    override func enable() {
        enable(screens: getXDRDisplays())
    }

    func enable(screens: [NSScreen]) {
        guard !screens.isEmpty else {
            reset(reason: "no compatible displays")
            return
        }

        isEnabled = true
        screenUpdate(screens: screens)
        startIntegrityPollIfNeeded()
        print("Enabled compatibility gamma technique")
    }

    override func enableScreen(screen: NSScreen) {
        guard let displayId = screen.displayId else {
            return
        }

        if gammaTables[displayId] == nil {
            gammaTables[displayId] = GammaTable.createFromCurrentGammaTable(displayId: displayId)
        }

        if let existing = overlayWindowControllers[displayId] {
            existing.updateScreen(screen: screen)
            return
        }

        let overlayWindowController = OverlayWindowController(screen: screen)
        overlayWindowControllers[displayId] = overlayWindowController
        let rect = NSRect(
            x: screen.frame.origin.x,
            y: screen.frame.origin.y,
            width: 1,
            height: 1
        )
        overlayWindowController.open(rect: rect)

        if screen.maximumExtendedDynamicRangeColorComponentValue > hdrReadyThreshold {
            hdrReadyDisplayIds.insert(displayId)
        }
    }

    override func disable() {
        reset(reason: "disabled")
    }

    func reset(reason: String) {
        cleanup(reason: reason)
    }

    override func adjustBrightness() {
        super.adjustBrightness()

        guard isEnabled else {
            return
        }

        for displayId in overlayWindowControllers.keys {
            guard let screen = screenForDisplay(displayId),
                  let gammaTable = gammaTables[displayId] else {
                continue
            }
            applyBrightness(screen: screen, displayId: displayId, gammaTable: gammaTable)
        }
    }

    override func screenUpdate(screens: [NSScreen]) {
        let activeDisplayIds = Set(screens.compactMap(\.displayId))
        let removedDisplayIds = overlayWindowControllers.keys.filter {
            !activeDisplayIds.contains($0)
        }

        for displayId in removedDisplayIds {
            removeDisplay(displayId)
        }

        for screen in screens {
            guard let displayId = screen.displayId else {
                continue
            }

            if let controller = overlayWindowControllers[displayId] {
                controller.updateScreen(screen: screen)
            } else {
                enableScreen(screen: screen)
            }
        }

        adjustBrightness()
        startIntegrityPollIfNeeded()
    }

    private var userBrightness: Float {
        BrightIntoshSettings.shared.fineGrainedBrightnessControl
            ? BrightIntoshSettings.shared.brightness
            : 1.0
    }

    private static func gammaFactor(
        userBrightness: Float,
        maxScreenBrightness: Float,
        referenceEdr: Float,
        currentEdr: CGFloat
    ) -> Float {
        let maximumEdr: Float = 16.0
        guard maximumEdr > referenceEdr else {
            return 1
        }

        let clampedEdr = min(max(Float(currentEdr), referenceEdr), maximumEdr)
        let fullFactor = 1 + maxScreenBrightness *
            (1 - (clampedEdr - referenceEdr) / (maximumEdr - referenceEdr))
        return 1 + (fullFactor - 1) * userBrightness
    }

    private func cleanup(reason: String) {
        print("Resetting compatibility gamma state: \(reason)")
        isEnabled = false
        stopIntegrityPoll()
        cancelAllFades()
        hdrReadyDisplayIds.removeAll()
        consecutiveRecoveryCounts.removeAll()

        Self.restoreSystemColorState()
        restoreCapturedGammaTables(reason: reason)

        for controller in overlayWindowControllers.values {
            controller.window?.close()
        }
        overlayWindowControllers.removeAll()
        gammaTables.removeAll()

        Self.restoreSystemColorState()
    }

    private func removeDisplay(_ displayId: CGDirectDisplayID) {
        cancelFade(displayId: displayId)
        hdrReadyDisplayIds.remove(displayId)
        consecutiveRecoveryCounts.removeValue(forKey: displayId)
        overlayWindowControllers[displayId]?.window?.close()
        if let gammaTable = gammaTables[displayId] {
            applyGammaTable(gammaTable, displayId: displayId)
        }
        gammaTables.removeValue(forKey: displayId)
        overlayWindowControllers.removeValue(forKey: displayId)
    }

    private func fadeGammaFactor(
        displayId: CGDirectDisplayID,
        gammaTable: GammaTable,
        targetFactor: Float
    ) {
        let state = fadeState(for: displayId)
        let targetChanged = state.targetFactor.map {
            abs($0 - targetFactor) > gammaFactorEpsilon
        } ?? true
        if !targetChanged {
            if state.task != nil || abs(state.appliedFactor - targetFactor) <= gammaFactorEpsilon {
                return
            }
        }

        let startFactor = state.appliedFactor
        state.targetFactor = targetFactor
        state.task?.cancel()

        if abs(startFactor - targetFactor) <= gammaFactorEpsilon {
            applyGammaTable(gammaTable, displayId: displayId, factor: targetFactor)
            state.appliedFactor = targetFactor
            state.task = nil
            return
        }

        state.task = Task { @MainActor in
            let startDate = Date()

            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startDate)
                let progress = min(1.0, elapsed / self.gammaFadeDuration)
                let easedProgress = progress * progress * (3.0 - 2.0 * progress)
                let nextFactor = startFactor +
                    ((targetFactor - startFactor) * Float(easedProgress))

                self.applyGammaTable(gammaTable, displayId: displayId, factor: nextFactor)
                state.appliedFactor = nextFactor

                if progress >= 1.0 {
                    break
                }

                try? await Task.sleep(for: self.gammaFadeFrameInterval)
            }

            guard !Task.isCancelled else {
                return
            }

            self.applyGammaTable(gammaTable, displayId: displayId, factor: targetFactor)
            state.appliedFactor = targetFactor
            state.targetFactor = targetFactor
            state.task = nil
        }
    }

    private func fadeState(for displayId: CGDirectDisplayID) -> FadeState {
        if let state = fadeStates[displayId] {
            return state
        }

        let state = FadeState()
        fadeStates[displayId] = state
        return state
    }

    private func cancelFade(displayId: CGDirectDisplayID) {
        fadeStates[displayId]?.task?.cancel()
        fadeStates.removeValue(forKey: displayId)
    }

    private func cancelAllFades() {
        for state in fadeStates.values {
            state.task?.cancel()
        }
        fadeStates.removeAll()
    }

    private func restoreCapturedGammaTables(reason: String) {
        for (displayId, gammaTable) in gammaTables {
            print("Restoring compatibility gamma table for display \(displayId) before \(reason)")
            applyGammaTable(gammaTable, displayId: displayId)
        }
    }

    private func applyGammaTable(
        _ gammaTable: GammaTable,
        displayId: CGDirectDisplayID,
        factor: Float = 1.0
    ) {
        Self.colorStateLock.lock()
        defer { Self.colorStateLock.unlock() }
        gammaTable.setTableForScreen(displayId: displayId, factor: factor)
    }

    private func applyBrightness(
        screen: NSScreen,
        displayId: CGDirectDisplayID,
        gammaTable: GammaTable
    ) {
        let (referenceEdr, maxScreenBrightness) = getScreenRefGamma(screen)
        let factor = Self.gammaFactor(
            userBrightness: userBrightness,
            maxScreenBrightness: maxScreenBrightness,
            referenceEdr: referenceEdr,
            currentEdr: screen.maximumExtendedDynamicRangeColorComponentValue
        )
        fadeGammaFactor(displayId: displayId, gammaTable: gammaTable, targetFactor: factor)
    }

    private func startIntegrityPollIfNeeded() {
        guard isEnabled, integrityPollTask == nil else {
            return
        }

        integrityPollTask = Task { @MainActor in
            defer { self.integrityPollTask = nil }

            while !Task.isCancelled, self.isEnabled {
                try? await Task.sleep(for: self.integrityPollInterval)
                guard !Task.isCancelled, self.isEnabled else {
                    return
                }
                self.recoverChangedDisplayState()
            }
        }
    }

    private func stopIntegrityPoll() {
        integrityPollTask?.cancel()
        integrityPollTask = nil
    }

    private func recoverChangedDisplayState() {
        for (displayId, gammaTable) in gammaTables {
            guard let screen = screenForDisplay(displayId) else {
                consecutiveRecoveryCounts.removeValue(forKey: displayId)
                hdrReadyDisplayIds.remove(displayId)
                continue
            }

            var recoveredState = false
            let hdrReady = screen.maximumExtendedDynamicRangeColorComponentValue > hdrReadyThreshold
            if hdrReady {
                let becameReady = hdrReadyDisplayIds.insert(displayId).inserted
                if becameReady {
                    applyBrightness(screen: screen, displayId: displayId, gammaTable: gammaTable)
                }
            } else {
                hdrReadyDisplayIds.remove(displayId)
                restoreGammaUntilHDRReturns(displayId: displayId, gammaTable: gammaTable)
                recreateHDROverlay(screen: screen, displayId: displayId)
                recoveredState = true
                print("Compatibility HDR state was reset for display \(displayId); recreated HDR trigger")
            }

            if let state = fadeStates[displayId],
               state.task == nil,
               let targetFactor = state.targetFactor,
               abs(state.appliedFactor - targetFactor) <= gammaFactorEpsilon,
               reapplyGammaTableIfNeeded(
                   gammaTable,
                   displayId: displayId,
                   factor: targetFactor
               ) {
                recoveredState = true
                print("Compatibility gamma table was reset for display \(displayId); reapplied factor \(targetFactor)")
            }

            guard recoveredState else {
                consecutiveRecoveryCounts.removeValue(forKey: displayId)
                continue
            }

            let recoveryCount = (consecutiveRecoveryCounts[displayId] ?? 0) + 1
            consecutiveRecoveryCounts[displayId] = recoveryCount
            print("Compatibility display state recovery \(recoveryCount)/\(maxConsecutiveRecoveryAttempts) for display \(displayId)")

            if recoveryCount >= maxConsecutiveRecoveryAttempts {
                handlePersistentDisplayConflict(displayId: displayId)
                return
            }
        }
    }

    private func restoreGammaUntilHDRReturns(
        displayId: CGDirectDisplayID,
        gammaTable: GammaTable
    ) {
        let state = fadeState(for: displayId)
        state.task?.cancel()
        state.task = nil
        state.targetFactor = nil
        state.appliedFactor = 1.0
        applyGammaTable(gammaTable, displayId: displayId)
    }

    private func recreateHDROverlay(screen: NSScreen, displayId: CGDirectDisplayID) {
        overlayWindowControllers[displayId]?.window?.close()
        overlayWindowControllers.removeValue(forKey: displayId)
        enableScreen(screen: screen)
    }

    private func reapplyGammaTableIfNeeded(
        _ gammaTable: GammaTable,
        displayId: CGDirectDisplayID,
        factor: Float
    ) -> Bool {
        Self.colorStateLock.lock()
        defer { Self.colorStateLock.unlock() }
        return gammaTable.reapplyIfLastValuesDrifted(
            displayId: displayId,
            factor: factor,
            tolerance: gammaTableTolerance
        )
    }

    private func screenForDisplay(_ displayId: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayId == displayId }
    }

    private func handlePersistentDisplayConflict(displayId: CGDirectDisplayID) {
        let reason = "Display \(displayId) repeatedly reset the HDR or gamma state after BrightIntosh applied it."
        print("Persistent compatibility display conflict detected: \(reason); disabling increased brightness")
        consecutiveRecoveryCounts.removeAll()

        if BrightIntoshSettings.shared.brightintoshActive {
            BrightIntoshSettings.shared.brightintoshActive = false
        } else {
            disable()
        }

        Task { @MainActor in
            await presentBrightnessFailurePrompt(reason: reason)
        }
    }

    func appendSupportDiagnostics(to report: inout String) {
        report += "Compatibility gamma technique:\n"
        report += " - Technique enabled: \(isEnabled)\n"
        report += " - Overlay display IDs: \(overlayWindowControllers.keys.sorted())\n"
        report += " - Gamma tables: \(gammaTables)\n"
        report += " - Fading display IDs: \(fadeStates.keys.sorted())\n"
        report += " - HDR-ready display IDs: \(hdrReadyDisplayIds.sorted())\n"
        report += " - Consecutive recovery counts: \(consecutiveRecoveryCounts)\n"
        report += " - Integrity poll active: \(integrityPollTask != nil)\n"
    }
}
