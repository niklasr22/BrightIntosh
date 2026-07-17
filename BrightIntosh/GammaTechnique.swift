//
//  GammaTechnique.swift
//  BrightIntosh
//

import Cocoa
import CoreGraphics

class GammaTable: CustomStringConvertible {
    static let tableSize: UInt32 = 256
    
    var redTable: [CGGammaValue] = [CGGammaValue](repeating: 0, count: Int(tableSize))
    var greenTable: [CGGammaValue] = [CGGammaValue](repeating: 0, count: Int(tableSize))
    var blueTable: [CGGammaValue] = [CGGammaValue](repeating: 0, count: Int(tableSize))
    
    var factor: Float = 0
    
    var description: String {
        let lastValues: String
        if let red = redTable.last,
           let green = greenTable.last,
           let blue = blueTable.last {
            lastValues = String(format: "%.4f, %.4f, %.4f", red, green, blue)
        } else {
            lastValues = "unavailable"
        }
        return "GammaTable(factor: \(factor), max: \(maximumValue), last RGB: \(lastValues))"
    }
    
    private init() {}
    
    static func createFromCurrentGammaTable(displayId: CGDirectDisplayID) -> GammaTable? {
        let table = GammaTable()
        var sampleCount: UInt32 = 0
        let result = CGGetDisplayTransferByTable(displayId, tableSize, &table.redTable, &table.greenTable, &table.blueTable, &sampleCount)
        guard result == CGError.success else { return nil }
        return table
    }
    
    @discardableResult
    func setTableForScreen(displayId: CGDirectDisplayID, factor: Float = 1.0) -> CGError {
        self.factor = factor
        var newRedTable = redTable
        var newGreenTable = greenTable
        var newBlueTable = blueTable
        
        for i in 0..<newRedTable.count {
            newRedTable[i] *= factor
            newGreenTable[i] *= factor
            newBlueTable[i] *= factor
        }
        return CGSetDisplayTransferByTable(displayId, GammaTable.tableSize, &newRedTable, &newGreenTable, &newBlueTable)
    }
    
    func reapplyIfLastValuesDrifted(displayId: CGDirectDisplayID, factor: Float, tolerance: CGGammaValue) -> String? {
        guard let currentTable = Self.createFromCurrentGammaTable(displayId: displayId),
              let redValue = redTable.last,
              let greenValue = greenTable.last,
              let blueValue = blueTable.last,
              let currentRedValue = currentTable.redTable.last,
              let currentGreenValue = currentTable.greenTable.last,
              let currentBlueValue = currentTable.blueTable.last else {
            return nil
        }

        let expectedRedValue = redValue * factor
        let expectedGreenValue = greenValue * factor
        let expectedBlueValue = blueValue * factor
        guard abs(currentRedValue - expectedRedValue) > tolerance ||
                abs(currentGreenValue - expectedGreenValue) > tolerance ||
                abs(currentBlueValue - expectedBlueValue) > tolerance else {
            return nil
        }

        let setResult = setTableForScreen(displayId: displayId, factor: factor)
        return String(
            format: "gamma endpoint drifted; expected RGB %.4f, %.4f, %.4f, observed RGB %.4f, %.4f, %.4f, factor %.4f, CGSet result %d",
            expectedRedValue,
            expectedGreenValue,
            expectedBlueValue,
            currentRedValue,
            currentGreenValue,
            currentBlueValue,
            factor,
            setResult.rawValue
        )
    }

    func currentLastValuesDescription(displayId: CGDirectDisplayID) -> String {
        guard let currentTable = Self.createFromCurrentGammaTable(displayId: displayId),
              let red = currentTable.redTable.last,
              let green = currentTable.greenTable.last,
              let blue = currentTable.blueTable.last else {
            return "unavailable"
        }
        return String(format: "%.4f, %.4f, %.4f", red, green, blue)
    }
    
    private var maximumValue: CGGammaValue {
        max(redTable.max() ?? 0, greenTable.max() ?? 0, blueTable.max() ?? 0)
    }
}

@MainActor
final class GammaTechnique: BrightnessTechnique {
    private(set) var isEnabled = false

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
    private var gammaCaptureFailure: String?
    private var lastFailureState: String?
    private var integrityPollTask: Task<Void, Never>?

    nonisolated private static let colorStateLock = NSLock()
    private let gammaFadeDuration: TimeInterval = 0.2
    private let gammaFadeFrameInterval: Duration = .milliseconds(16)
    private let gammaFactorEpsilon: Float = 0.001
    private let integrityPollStartupDelay: Duration = .seconds(60)
    private let integrityPollInterval: Duration = .seconds(2)
    private let gammaTableTolerance: CGGammaValue = 0.003
    private let hdrReadyThreshold: CGFloat = 1.05
    private let maxConsecutiveRecoveryAttempts = 3

    nonisolated static func restoreSystemColorState() {
        colorStateLock.lock()
        defer { colorStateLock.unlock() }
        CGDisplayRestoreColorSyncSettings()
    }

    func enable(screens: [NSScreen]) {
        guard !screens.isEmpty else {
            cleanup(reason: "no compatible displays")
            return
        }

        isEnabled = true
        BrightnessDiagnosticHistory.record(
            "Gamma technique enabled for displays \(screens.compactMap(\.displayId).sorted())"
        )
        screenUpdate(screens: screens)
        print("Enabled gamma technique")
    }

    private func enableScreen(screen: NSScreen) {
        guard let displayId = screen.displayId else {
            return
        }

        if gammaTables[displayId] == nil {
            guard let gammaTable = GammaTable.createFromCurrentGammaTable(displayId: displayId) else {
                handleGammaCaptureFailure(displayId: displayId)
                return
            }
            gammaTables[displayId] = gammaTable
            BrightnessDiagnosticHistory.record(
                "Captured gamma table for display \(displayId): \(gammaTable)"
            )
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
        BrightnessDiagnosticHistory.record(
            "Created HDR trigger for display \(displayId); max EDR \(String(format: "%.4f", screen.maximumExtendedDynamicRangeColorComponentValue))"
        )

        if screen.maximumExtendedDynamicRangeColorComponentValue > hdrReadyThreshold {
            hdrReadyDisplayIds.insert(displayId)
        }
    }

    func disable() {
        cleanup(reason: "disabled")
    }

    func updateBrightness(reason: BrightnessUpdateReason) {
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

    func screenUpdate(screens: [NSScreen]) {
        let activeDisplayIds = Set(screens.compactMap(\.displayId))
        let removedDisplayIds = overlayWindowControllers.keys.filter {
            !activeDisplayIds.contains($0)
        }

        for displayId in removedDisplayIds {
            removeDisplay(displayId)
        }

        for screen in screens {
            guard isEnabled else { break }
            guard let displayId = screen.displayId else {
                continue
            }

            if let controller = overlayWindowControllers[displayId] {
                controller.updateScreen(screen: screen)
            } else {
                enableScreen(screen: screen)
            }
        }

        updateBrightness(reason: .displayParametersChanged)
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
        print("Resetting gamma state: \(reason)")
        BrightnessDiagnosticHistory.record(
            "Cleaning up gamma technique: \(reason); overlays \(overlayWindowControllers.keys.sorted()), gamma displays \(gammaTables.keys.sorted())"
        )
        isEnabled = false
        integrityPollTask?.cancel()
        integrityPollTask = nil
        for state in fadeStates.values {
            state.task?.cancel()
        }
        fadeStates.removeAll()
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
        BrightnessDiagnosticHistory.record("Removing display \(displayId) from gamma technique")
        fadeStates[displayId]?.task?.cancel()
        fadeStates.removeValue(forKey: displayId)
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
            recordCompletedGammaApplication(
                gammaTable,
                displayId: displayId,
                factor: targetFactor
            )
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
            self.recordCompletedGammaApplication(
                gammaTable,
                displayId: displayId,
                factor: targetFactor
            )
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

    private func restoreCapturedGammaTables(reason: String) {
        for (displayId, gammaTable) in gammaTables {
            print("Restoring gamma table for display \(displayId) before \(reason)")
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
        let result = gammaTable.setTableForScreen(displayId: displayId, factor: factor)
        if result != .success {
            BrightnessDiagnosticHistory.record(
                "CGSetDisplayTransferByTable failed for display \(displayId), factor \(String(format: "%.4f", factor)), error \(result.rawValue)"
            )
        }
    }

    private func recordCompletedGammaApplication(
        _ gammaTable: GammaTable,
        displayId: CGDirectDisplayID,
        factor: Float
    ) {
        let readback = gammaTable.currentLastValuesDescription(displayId: displayId)
        BrightnessDiagnosticHistory.record(
            "Applied final gamma for display \(displayId); factor \(String(format: "%.4f", factor)), readback RGB \(readback)"
        )
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

            BrightnessDiagnosticHistory.record("Gamma integrity polling scheduled to start in 60s")
            try? await Task.sleep(for: self.integrityPollStartupDelay)
            guard !Task.isCancelled, self.isEnabled else {
                return
            }
            BrightnessDiagnosticHistory.record("Gamma integrity polling started")

            while !Task.isCancelled, self.isEnabled {
                try? await Task.sleep(for: self.integrityPollInterval)
                guard !Task.isCancelled, self.isEnabled else {
                    return
                }
                self.recoverChangedDisplayState()
            }
        }
    }

    private func recoverChangedDisplayState() {
        for (displayId, gammaTable) in gammaTables {
            guard let screen = screenForDisplay(displayId) else {
                consecutiveRecoveryCounts.removeValue(forKey: displayId)
                hdrReadyDisplayIds.remove(displayId)
                continue
            }

            var recoveryDetails: [String] = []
            let maxEdr = screen.maximumExtendedDynamicRangeColorComponentValue
            let hdrReady = maxEdr > hdrReadyThreshold
            if hdrReady {
                let becameReady = hdrReadyDisplayIds.insert(displayId).inserted
                if becameReady {
                    BrightnessDiagnosticHistory.record(
                        "Display \(displayId) became HDR ready; max EDR \(String(format: "%.4f", maxEdr))"
                    )
                    applyBrightness(screen: screen, displayId: displayId, gammaTable: gammaTable)
                }
            } else {
                hdrReadyDisplayIds.remove(displayId)
                restoreGammaUntilHDRReturns(displayId: displayId, gammaTable: gammaTable)
                recreateHDROverlay(screen: screen, displayId: displayId)
                let edrDetails = String(
                    format: "HDR was not ready; max EDR %.4f, threshold %.2f",
                    maxEdr,
                    hdrReadyThreshold
                )
                recoveryDetails.append(edrDetails)
                print("HDR state was reset for display \(displayId); recreated HDR trigger")
            }

            if let state = fadeStates[displayId],
               state.task == nil,
               let targetFactor = state.targetFactor,
               abs(state.appliedFactor - targetFactor) <= gammaFactorEpsilon,
               let gammaRecoveryDetails = reapplyGammaTableIfNeeded(
                   gammaTable,
                   displayId: displayId,
                   factor: targetFactor
               ) {
                recoveryDetails.append(gammaRecoveryDetails)
                print("Gamma table was reset for display \(displayId); reapplied factor \(targetFactor)")
            }

            guard !recoveryDetails.isEmpty else {
                if let previousCount = consecutiveRecoveryCounts[displayId] {
                    BrightnessDiagnosticHistory.record(
                        "Display \(displayId) recovered normally after \(previousCount) integrity recoveries"
                    )
                }
                consecutiveRecoveryCounts.removeValue(forKey: displayId)
                continue
            }

            let recoveryCount = (consecutiveRecoveryCounts[displayId] ?? 0) + 1
            consecutiveRecoveryCounts[displayId] = recoveryCount
            BrightnessDiagnosticHistory.record(
                "Integrity recovery \(recoveryCount)/\(maxConsecutiveRecoveryAttempts) for display \(displayId): \(recoveryDetails.joined(separator: "; "))"
            )
            print("Display state recovery \(recoveryCount)/\(maxConsecutiveRecoveryAttempts) for display \(displayId)")

            if recoveryCount >= maxConsecutiveRecoveryAttempts {
                handlePersistentDisplayConflict(
                    displayId: displayId,
                    recoveryDetails: recoveryDetails
                )
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
    ) -> String? {
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

    private func handlePersistentDisplayConflict(
        displayId: CGDirectDisplayID,
        recoveryDetails: [String]
    ) {
        let reason = "Display \(displayId) repeatedly reset the HDR or gamma state after BrightIntosh applied it."
        captureFailureState(
            displayId: displayId,
            reason: reason,
            recoveryDetails: recoveryDetails
        )
        print("Persistent display conflict detected: \(reason); disabling increased brightness")
        BrightnessDiagnosticHistory.record("Gamma technique failure: \(reason)")
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

    private func handleGammaCaptureFailure(displayId: CGDirectDisplayID) {
        let reason = "CGGetDisplayTransferByTable failed for display \(displayId)."
        gammaCaptureFailure = reason
        captureFailureState(displayId: displayId, reason: reason, recoveryDetails: [reason])
        print("Gamma capture failure detected: \(reason); disabling increased brightness")
        BrightnessDiagnosticHistory.record("Gamma technique failure: \(reason)")

        if BrightIntoshSettings.shared.brightintoshActive {
            BrightIntoshSettings.shared.brightintoshActive = false
        } else {
            disable()
        }

        Task { @MainActor in
            await presentBrightnessFailurePrompt(reason: reason)
        }
    }

    private func captureFailureState(
        displayId: CGDirectDisplayID,
        reason: String,
        recoveryDetails: [String]
    ) {
        let maxEdr = screenForDisplay(displayId)?.maximumExtendedDynamicRangeColorComponentValue
        let fadeState = fadeStates[displayId]
        lastFailureState = """
         - Reason: \(reason)
         - Display ID: \(displayId)
         - Increased brightness setting: \(BrightIntoshSettings.shared.brightintoshActive)
         - Technique enabled: \(isEnabled)
         - Max EDR: \(maxEdr.map { String(format: "%.4f", $0) } ?? "unavailable")
         - Display event timing: \(SupportReportContext.displayEventTiming())
         - Recovery details: \(recoveryDetails.joined(separator: "; "))
         - Consecutive recovery count: \(consecutiveRecoveryCounts[displayId] ?? 0)
         - Gamma table: \(gammaTables[displayId].map(String.init(describing:)) ?? "none")
         - Fade applied factor: \(fadeState.map { String(format: "%.4f", $0.appliedFactor) } ?? "none")
         - Fade target factor: \(fadeState?.targetFactor.map { String(format: "%.4f", $0) } ?? "none")
         - Fade active: \(fadeState?.task != nil)
         - HDR ready: \(hdrReadyDisplayIds.contains(displayId))
         - Overlay display IDs: \(overlayWindowControllers.keys.sorted())
        """
    }

    func appendSupportDiagnostics(to report: inout String) {
        if let lastFailureState {
            report += "Gamma state at failure:\n\(lastFailureState)\n"
        }
        report += "Gamma technique:\n"
        report += " - Technique enabled: \(isEnabled)\n"
        report += " - Overlay display IDs: \(overlayWindowControllers.keys.sorted())\n"
        report += " - Gamma tables: \(gammaTables)\n"
        report += " - Fading display IDs: \(fadeStates.keys.sorted())\n"
        report += " - HDR-ready display IDs: \(hdrReadyDisplayIds.sorted())\n"
        report += " - Consecutive recovery counts: \(consecutiveRecoveryCounts)\n"
        report += " - Gamma capture failure: \(gammaCaptureFailure ?? "none")\n"
        report += " - Integrity poll active: \(integrityPollTask != nil)\n"
    }
}
