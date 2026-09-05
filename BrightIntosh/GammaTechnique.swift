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

    private enum HDRRecoveryState {
        case waitingForDisplayWake
        case confirmingLoss(until: Date)
        case waitingForHDR(until: Date)
        case retainingTrigger(until: Date)
        case monitoringUnavailable
    }

    private enum HDRAvailability {
        case unavailable
        case ready(newlyEngaged: Bool)
    }

    private final class DisplayRecoveryState {
        var hdrState: HDRRecoveryState?
        var isHDRReady = false
        var consecutiveGammaRecoveries = 0
        var gammaConflictSince: Date?
        var gammaConflictFactor: Float?
        var lastHDREngagementObservationDate: Date?
        var hdrReadySince: Date?
        var hasRecreatedTriggerDuringOutage = false

        func resetHDR(to state: HDRRecoveryState? = nil, ready: Bool = false) {
            hdrState = state
            isHDRReady = ready
            hdrReadySince = nil
            lastHDREngagementObservationDate = nil
            hasRecreatedTriggerDuringOutage = false
            clearGammaConflict()
        }

        func clearGammaConflict() {
            consecutiveGammaRecoveries = 0
            gammaConflictSince = nil
            gammaConflictFactor = nil
        }
    }

    private final class FadeState {
        var appliedFactor: Float = 1.0
        var targetFactor: Float?
        var task: Task<Void, Never>?
        var upwardAdjustmentTask: Task<Void, Never>?
        var pendingUpwardFactor: Float?
    }

    private struct GammaApplicationContext {
        let reason: BrightnessUpdateReason
        let inputEdr: CGFloat
    }

    private var overlayWindowControllers: [CGDirectDisplayID: OverlayWindowController] = [:]
    private var gammaTables: [CGDirectDisplayID: GammaTable] = [:]
    private var fadeStates: [CGDirectDisplayID: FadeState] = [:]
    private var displayRecoveryStates: [CGDirectDisplayID: DisplayRecoveryState] = [:]
    private var gammaCaptureFailures: [CGDirectDisplayID: String] = [:]
    private var gammaConflictDisplayIds: Set<CGDirectDisplayID> = []
    private var lastFailureState: String?
    private var hdrRecoverySummaries: [CGDirectDisplayID: (onset: String, beforeRecreation: String?, latest: String)] = [:]
    private var integrityPollTask: Task<Void, Never>?
    private var gammaConflictChecksAllowedAfter = Date.distantPast
    private var nextGammaIntegrityCheck = Date.distantPast
    nonisolated private static let colorStateLock = NSLock()
    private let gammaFadeDuration: TimeInterval = 0.2
    private let gammaFadeFrameInterval: Duration = .milliseconds(16)
    private let gammaFactorEpsilon: Float = 0.001
    private let upwardGammaStabilizationDelay: Duration = .milliseconds(1500)
    private let integrityPollInterval: Duration = .seconds(2)
    private let maximumIntegrityPollGap: TimeInterval = 10
    private let integrityPollResumeDelay: TimeInterval = 5
    private let gammaTableTolerance: CGGammaValue = 0.003
    private let gammaConflictGraceDuration: TimeInterval = 15
    private let hdrReadyThreshold: CGFloat = 1.05
    private let hdrLossConfirmationDuration: TimeInterval = 1.5
    private let hdrRecoveryStabilizationDuration: TimeInterval = 2
    private let hdrEngagementTimeout: TimeInterval = 10
    private let hdrTriggerRetentionDuration: TimeInterval = 30
    private let maxConsecutiveGammaRecoveryAttempts = 3
    private let gammaConflictConfirmationDuration: TimeInterval = 6

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

        if !isEnabled {
            gammaConflictDisplayIds.removeAll()
            // Retry capture and re-arm reporting for failures that persist after a restart.
            gammaCaptureFailures.removeAll()
        }
        isEnabled = true
        gammaConflictChecksAllowedAfter = Date().addingTimeInterval(gammaConflictGraceDuration)
        BrightnessDiagnosticHistory.record(
            "Gamma technique enabled for displays \(screens.compactMap(\.displayId).sorted())"
        )
        updateScreens(screens, brightnessUpdateReason: .techniqueEnabled)
        print("Enabled gamma technique")
    }

    private func enableScreen(screen: NSScreen) {
        guard let displayId = screen.displayId else {
            return
        }
        guard !gammaConflictDisplayIds.contains(displayId) else { return }

        if gammaTables[displayId] == nil {
            guard let gammaTable = GammaTable.createFromCurrentGammaTable(displayId: displayId) else {
                handleGammaCaptureFailure(displayId: displayId)
                return
            }
            gammaTables[displayId] = gammaTable
            if gammaCaptureFailures.removeValue(forKey: displayId) != nil {
                BrightnessDiagnosticHistory.record(
                    "Display \(displayId) recovered gamma-table access; resuming its brightness independently"
                )
            }
            BrightnessDiagnosticHistory.record(
                "Captured gamma table for display \(displayId): \(gammaTable)"
            )
        }

        let recoveryState = displayRecoveryState(for: displayId)
        if CGDisplayIsAsleep(displayId) != 0 {
            recoveryState.resetHDR(to: .waitingForDisplayWake)
            notifyHDRCooldownEnded(displayId: displayId)
            BrightnessDiagnosticHistory.record(
                "Deferring HDR engagement for sleeping display \(displayId)"
            )
            return
        }

        recoveryState.resetHDR()
        _ = beginHDREngagement(screen: screen, displayId: displayId)
    }

    private func beginHDREngagement(
        screen: NSScreen,
        displayId: CGDirectDisplayID
    ) -> HDRAvailability {
        let preTriggerEdr = screen.maximumExtendedDynamicRangeColorComponentValue
        let triggerWasCreated: Bool
        if let existing = overlayWindowControllers[displayId] {
            existing.updateScreen(screen: screen)
            triggerWasCreated = false
        } else {
            let overlayWindowController = OverlayWindowController(screen: screen)
            overlayWindowControllers[displayId] = overlayWindowController
            let rect = NSRect(
                x: screen.frame.origin.x,
                y: screen.frame.origin.y,
                width: 1,
                height: 1
            )
            overlayWindowController.open(rect: rect)
            triggerWasCreated = true
        }
        let recoveryState = displayRecoveryState(for: displayId)
        recoveryState.lastHDREngagementObservationDate = nil
        recoveryState.hdrState = .waitingForHDR(
            until: Date().addingTimeInterval(hdrEngagementTimeout)
        )
        let immediateEdr = screenForDisplay(displayId)?
            .maximumExtendedDynamicRangeColorComponentValue
        BrightnessDiagnosticHistory.record(
            "\(triggerWasCreated ? "Created" : "Updated") HDR trigger for display \(displayId); " +
            "pre-trigger max EDR \(String(format: "%.4f", preTriggerEdr)), " +
            "immediate max EDR \(immediateEdr.map { String(format: "%.4f", $0) } ?? "unavailable")"
        )

        guard hdrIsReady(screen) else {
            recoveryState.isHDRReady = false
            recoveryState.hdrReadySince = nil
            if !recoveryState.hasRecreatedTriggerDuringOutage {
                recordHDRRecovery(screen: screen, displayId: displayId, message: "Waiting for initial HDR engagement", newOutage: true)
            }
            return .unavailable
        }

        if recoveryState.hasRecreatedTriggerDuringOutage {
            recoveryState.isHDRReady = false
            recoveryState.hdrReadySince = Date()
            BrightnessDiagnosticHistory.record(
                "Recreated HDR trigger produced a recovery candidate for display \(displayId); " +
                hdrDiagnosticContext(screen: screen, displayId: displayId)
            )
            return .unavailable
        }

        recoveryState.resetHDR(ready: true)
        return .ready(newlyEngaged: true)
    }

    private func closeHDROverlay(displayId: CGDirectDisplayID) {
        overlayWindowControllers[displayId]?.window?.close()
        overlayWindowControllers.removeValue(forKey: displayId)
    }

    private func hdrIsReady(_ screen: NSScreen) -> Bool {
        screen.maximumExtendedDynamicRangeColorComponentValue > hdrReadyThreshold
    }

    private func displayRecoveryState(
        for displayId: CGDirectDisplayID
    ) -> DisplayRecoveryState {
        if let state = displayRecoveryStates[displayId] {
            return state
        }
        let state = DisplayRecoveryState()
        displayRecoveryStates[displayId] = state
        return state
    }

    func disable() {
        cleanup(reason: "disabled")
    }

    func updateBrightness(reason: BrightnessUpdateReason) {
        guard isEnabled else {
            return
        }

        for displayId in gammaTables.keys {
            guard isEnabled else { return }
            guard let screen = screenForDisplay(displayId),
                  let gammaTable = gammaTables[displayId] else {
                continue
            }
            updateDisplayBrightness(
                screen: screen,
                displayId: displayId,
                gammaTable: gammaTable,
                reason: reason
            )
        }
    }

    func screenUpdate(screens: [NSScreen]) {
        updateScreens(screens, brightnessUpdateReason: .displayParametersChanged)
    }

    private func updateScreens(
        _ screens: [NSScreen],
        brightnessUpdateReason: BrightnessUpdateReason
    ) {
        let activeDisplayIds = Set(screens.compactMap(\.displayId))
        let trackedDisplayIds = Set(gammaTables.keys)
            .union(displayRecoveryStates.keys)
            .union(gammaCaptureFailures.keys)
            .union(gammaConflictDisplayIds)
        let removedDisplayIds = trackedDisplayIds.filter {
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

        updateBrightness(reason: brightnessUpdateReason)
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
            state.upwardAdjustmentTask?.cancel()
        }
        fadeStates.removeAll()

        for displayId in displayRecoveryStates.keys {
            notifyHDRCooldownEnded(displayId: displayId)
        }
        displayRecoveryStates.removeAll()

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
        fadeStates[displayId]?.upwardAdjustmentTask?.cancel()
        fadeStates.removeValue(forKey: displayId)
        displayRecoveryStates.removeValue(forKey: displayId)
        gammaCaptureFailures.removeValue(forKey: displayId)
        gammaConflictDisplayIds.remove(displayId)
        notifyHDRCooldownEnded(displayId: displayId)
        closeHDROverlay(displayId: displayId)
        if let gammaTable = gammaTables[displayId] {
            applyGammaTable(gammaTable, displayId: displayId)
        }
        gammaTables.removeValue(forKey: displayId)
    }

    private func fadeGammaFactor(
        displayId: CGDirectDisplayID,
        gammaTable: GammaTable,
        targetFactor: Float,
        context: GammaApplicationContext
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
                factor: targetFactor,
                context: context
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
                factor: targetFactor,
                context: context
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
        factor: Float,
        context: GammaApplicationContext
    ) {
        let readback = gammaTable.currentLastValuesDescription(displayId: displayId)
        let factorDescription = String(format: "%.4f", factor)
        let inputEdrDescription = String(format: "%.4f", context.inputEdr)
        let completionEdr = screenForDisplay(displayId).map {
            String(format: "%.4f", $0.maximumExtendedDynamicRangeColorComponentValue)
        } ?? "unavailable"
        BrightnessDiagnosticHistory.record(
            "Applied final gamma for display \(displayId); " +
            "factor \(factorDescription), reason \(context.reason.rawValue), " +
            "input max EDR \(inputEdrDescription), completion max EDR \(completionEdr), " +
            "readback RGB \(readback)"
        )
    }

    private func applyBoostedBrightness(
        screen: NSScreen,
        displayId: CGDirectDisplayID,
        gammaTable: GammaTable,
        reason: BrightnessUpdateReason,
        applyImmediately: Bool = false
    ) {
        let currentEdr = screen.maximumExtendedDynamicRangeColorComponentValue
        let (referenceEdr, maxScreenBrightness) = getScreenRefGamma(screen)
        let factor = Self.gammaFactor(
            userBrightness: userBrightness,
            maxScreenBrightness: maxScreenBrightness,
            referenceEdr: referenceEdr,
            currentEdr: currentEdr
        )

        let state = fadeState(for: displayId)
        let currentFactor = max(state.appliedFactor, state.targetFactor ?? state.appliedFactor)
        let shouldStabilizeUpwardAdjustment =
            !applyImmediately &&
            (reason == .displayParametersChanged || reason == .integrityPoll)

        if shouldStabilizeUpwardAdjustment,
           factor > currentFactor + gammaFactorEpsilon {
            scheduleUpwardGammaAdjustment(
                displayId: displayId,
                initialFactor: currentFactor,
                proposedFactor: factor,
                inputEdr: currentEdr,
                reason: reason
            )
            return
        }

        if applyImmediately {
            BrightnessDiagnosticHistory.record(
                "Applying gamma immediately after HDR engagement for display \(displayId)"
            )
        }
        cancelUpwardGammaAdjustment(displayId: displayId)
        fadeGammaFactor(
            displayId: displayId,
            gammaTable: gammaTable,
            targetFactor: factor,
            context: GammaApplicationContext(reason: reason, inputEdr: currentEdr)
        )
    }

    private func scheduleUpwardGammaAdjustment(
        displayId: CGDirectDisplayID,
        initialFactor: Float,
        proposedFactor: Float,
        inputEdr: CGFloat,
        reason: BrightnessUpdateReason
    ) {
        let state = fadeState(for: displayId)
        if state.upwardAdjustmentTask != nil,
           let pendingFactor = state.pendingUpwardFactor,
           abs(pendingFactor - proposedFactor) <= gammaFactorEpsilon {
            return
        }
        state.upwardAdjustmentTask?.cancel()
        state.pendingUpwardFactor = proposedFactor
        BrightnessDiagnosticHistory.record(
            "Deferring upward gamma for display \(displayId) until EDR stabilizes; " +
            "factor \(String(format: "%.4f", initialFactor)) -> " +
            "\(String(format: "%.4f", proposedFactor)), max EDR " +
            "\(String(format: "%.4f", inputEdr)), reason \(reason.rawValue)"
        )

        state.upwardAdjustmentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.upwardGammaStabilizationDelay)
            guard !Task.isCancelled, self.isEnabled else {
                return
            }
            state.upwardAdjustmentTask = nil
            state.pendingUpwardFactor = nil

            guard let screen = self.screenForDisplay(displayId),
                  let gammaTable = self.gammaTables[displayId],
                  case .ready = self.updateHDRAvailability(
                    screen: screen,
                    displayId: displayId,
                    gammaTable: gammaTable
                  ) else {
                return
            }

            let currentEdr = screen.maximumExtendedDynamicRangeColorComponentValue
            let (referenceEdr, maxScreenBrightness) = getScreenRefGamma(screen)
            let stabilizedFactor = Self.gammaFactor(
                userBrightness: self.userBrightness,
                maxScreenBrightness: maxScreenBrightness,
                referenceEdr: referenceEdr,
                currentEdr: currentEdr
            )
            guard abs(stabilizedFactor - proposedFactor) <= self.gammaFactorEpsilon else {
                self.applyBoostedBrightness(
                    screen: screen, displayId: displayId, gammaTable: gammaTable, reason: reason
                )
                return
            }
            let currentFactor = max(
                state.appliedFactor,
                state.targetFactor ?? state.appliedFactor
            )
            guard stabilizedFactor > currentFactor + self.gammaFactorEpsilon else {
                return
            }

            BrightnessDiagnosticHistory.record(
                "Applying stabilized upward gamma for display \(displayId); " +
                "factor \(String(format: "%.4f", currentFactor)) -> " +
                "\(String(format: "%.4f", stabilizedFactor)), max EDR " +
                "\(String(format: "%.4f", currentEdr))"
            )
            self.fadeGammaFactor(
                displayId: displayId,
                gammaTable: gammaTable,
                targetFactor: stabilizedFactor,
                context: GammaApplicationContext(
                    reason: reason,
                    inputEdr: currentEdr
                )
            )
        }
    }

    private func cancelUpwardGammaAdjustment(displayId: CGDirectDisplayID) {
        guard let state = fadeStates[displayId] else { return }
        state.upwardAdjustmentTask?.cancel()
        state.upwardAdjustmentTask = nil
        state.pendingUpwardFactor = nil
    }

    private func updateDisplayBrightness(
        screen: NSScreen,
        displayId: CGDirectDisplayID,
        gammaTable: GammaTable,
        reason: BrightnessUpdateReason
    ) {
        guard case let .ready(newlyEngaged) = updateHDRAvailability(
            screen: screen,
            displayId: displayId,
            gammaTable: gammaTable
        ) else {
            return
        }
        applyBoostedBrightness(
            screen: screen,
            displayId: displayId,
            gammaTable: gammaTable,
            reason: reason,
            applyImmediately: newlyEngaged
        )
    }

    private func startIntegrityPollIfNeeded() {
        guard isEnabled, integrityPollTask == nil else {
            return
        }

        let pollScheduledAt = Date()
        integrityPollTask = Task { @MainActor in
            defer { self.integrityPollTask = nil }

            BrightnessDiagnosticHistory.record("Gamma integrity polling started")
            let pollStartedAt = Date()
            let startupDelay = pollStartedAt.timeIntervalSince(pollScheduledAt)
            if startupDelay > self.maximumIntegrityPollGap {
                self.deferRecoveryAfterLongPollGap(
                    elapsed: startupDelay,
                    now: pollStartedAt
                )
            }
            var previousPollDate = pollStartedAt

            while !Task.isCancelled, self.isEnabled {
                try? await Task.sleep(for: self.currentIntegrityPollInterval)
                guard !Task.isCancelled, self.isEnabled else {
                    return
                }
                let now = Date()
                let elapsed = now.timeIntervalSince(previousPollDate)
                previousPollDate = now
                if elapsed > self.maximumIntegrityPollGap {
                    self.deferRecoveryAfterLongPollGap(elapsed: elapsed, now: now)
                    continue
                }
                self.recoverChangedDisplayState()
            }
        }
    }

    private var currentIntegrityPollInterval: Duration {
        let needsFastRecoveryPolling = displayRecoveryStates.values.contains { state in
            if state.hdrReadySince != nil { return true }
            switch state.hdrState {
            case .confirmingLoss, .waitingForHDR, .retainingTrigger:
                return true
            case .waitingForDisplayWake, .monitoringUnavailable, nil:
                return false
            }
        }
        return needsFastRecoveryPolling ? .milliseconds(250) : integrityPollInterval
    }

    private func deferRecoveryAfterLongPollGap(elapsed: TimeInterval, now: Date) {
        let earliestRetryDate = now.addingTimeInterval(integrityPollResumeDelay)
        BrightnessDiagnosticHistory.record(
            "Gamma integrity polling resumed after \(String(format: "%.1f", elapsed))s; deferring HDR recovery for \(Int(integrityPollResumeDelay))s"
        )

        for (displayId, gammaTable) in gammaTables {
            guard let screen = screenForDisplay(displayId) else {
                continue
            }
            let recoveryState = displayRecoveryState(for: displayId)

            recoveryState.hdrReadySince = nil
            if CGDisplayIsAsleep(displayId) != 0 {
                _ = updateHDRAvailability(screen: screen, displayId: displayId, gammaTable: gammaTable)
                continue
            }

            guard !hdrIsReady(screen) else { continue }
            restoreGammaUntilHDRReturns(displayId: displayId, gammaTable: gammaTable)
            recoveryState.isHDRReady = false
            beginHDRRecovery(
                screen: screen,
                displayId: displayId,
                reason: "integrity polling resumed after a long gap",
                retryDelay: earliestRetryDate.timeIntervalSince(now)
            )
        }
    }

    private func recoverChangedDisplayState() {
        retryFailedGammaCaptures()
        let now = Date()
        let checkGamma = now >= nextGammaIntegrityCheck
        if checkGamma { nextGammaIntegrityCheck = now.addingTimeInterval(2) }

        for (displayId, gammaTable) in gammaTables {
            guard isEnabled else { return }
            let recoveryState = displayRecoveryState(for: displayId)
            guard let screen = screenForDisplay(displayId) else {
                recoveryState.clearGammaConflict()
                recoveryState.isHDRReady = false
                continue
            }

            guard case let .ready(newlyEngaged) = updateHDRAvailability(
                screen: screen,
                displayId: displayId,
                gammaTable: gammaTable
            ) else {
                recoveryState.clearGammaConflict()
                continue
            }

            applyBoostedBrightness(
                screen: screen,
                displayId: displayId,
                gammaTable: gammaTable,
                reason: .integrityPoll,
                applyImmediately: newlyEngaged
            )

            // HDR recovery can poll faster without accelerating gamma conflict detection.
            guard checkGamma else { continue }
            if let state = fadeStates[displayId],
               state.task == nil,
               state.upwardAdjustmentTask == nil,
               let targetFactor = state.targetFactor,
               abs(state.appliedFactor - targetFactor) <= gammaFactorEpsilon,
               let gammaRecoveryDetails = reapplyGammaTableIfNeeded(
                   gammaTable,
                   displayId: displayId,
                   factor: targetFactor
               ) {
                // Repair immediately during grace, but do not classify startup resets as conflicts.
                guard now >= gammaConflictChecksAllowedAfter else {
                    recoveryState.clearGammaConflict()
                    BrightnessDiagnosticHistory.record("Repaired gamma during startup grace for display \(displayId): \(gammaRecoveryDetails)")
                    continue
                }
                if recoveryState.gammaConflictFactor.map({ abs($0 - targetFactor) > gammaFactorEpsilon }) ?? true {
                    recoveryState.clearGammaConflict()
                    recoveryState.gammaConflictFactor = targetFactor
                    recoveryState.gammaConflictSince = now
                }
                recoveryState.consecutiveGammaRecoveries += 1
                let recoveryCount = recoveryState.consecutiveGammaRecoveries
                let conflictDuration = now.timeIntervalSince(recoveryState.gammaConflictSince ?? now)
                BrightnessDiagnosticHistory.record(
                    "Gamma recovery \(recoveryCount) over \(String(format: "%.1f", conflictDuration))s for display \(displayId): \(gammaRecoveryDetails)"
                )
                print("Gamma table was reset for display \(displayId); reapplied factor \(targetFactor)")
                if recoveryCount >= maxConsecutiveGammaRecoveryAttempts,
                   conflictDuration >= gammaConflictConfirmationDuration {
                    handlePersistentGammaConflict(
                        displayId: displayId,
                        recoveryDetails: gammaRecoveryDetails
                    )
                    continue
                }
            } else if recoveryState.consecutiveGammaRecoveries > 0 {
                let previousCount = recoveryState.consecutiveGammaRecoveries
                recoveryState.clearGammaConflict()
                BrightnessDiagnosticHistory.record(
                    "Display \(displayId) gamma conflict sequence cleared after \(previousCount) recoveries"
                )
            }
        }
    }

    private func retryFailedGammaCaptures() {
        for displayId in Array(gammaCaptureFailures.keys) {
            guard isEnabled, let screen = screenForDisplay(displayId) else {
                continue
            }
            enableScreen(screen: screen)
        }
    }

    private func updateHDRAvailability(
        screen: NSScreen,
        displayId: CGDirectDisplayID,
        gammaTable: GammaTable
    ) -> HDRAvailability {
        let now = Date()
        let recoveryState = displayRecoveryState(for: displayId)

        if CGDisplayIsAsleep(displayId) != 0 {
            restoreGammaUntilHDRReturns(displayId: displayId, gammaTable: gammaTable)
            closeHDROverlay(displayId: displayId)
            if case .waitingForDisplayWake = recoveryState.hdrState {
                return .unavailable
            }
            recoveryState.resetHDR(to: .waitingForDisplayWake)
            notifyHDRCooldownEnded(displayId: displayId)
            BrightnessDiagnosticHistory.record(
                "Display \(displayId) is asleep; deferring HDR recovery"
            )
            return .unavailable
        }

        if case .waitingForDisplayWake = recoveryState.hdrState {
            recoveryState.resetHDR()
            BrightnessDiagnosticHistory.record(
                "Display \(displayId) is awake; starting HDR engagement"
            )
            return beginHDREngagement(screen: screen, displayId: displayId)
        }

        if let hdrState = recoveryState.hdrState {
            if hdrIsReady(screen) {
                return stabilizedHDRRecoveryAvailability(
                    screen: screen,
                    displayId: displayId,
                    recoveryState: recoveryState,
                    now: now
                )
            }

            recoveryState.hdrReadySince = nil
            restoreGammaUntilHDRReturns(displayId: displayId, gammaTable: gammaTable)

            switch hdrState {
            case .waitingForDisplayWake:
                return .unavailable

            case let .confirmingLoss(until):
                guard now >= until else { return .unavailable }
                beginHDRRecovery(screen: screen, displayId: displayId, reason: "HDR loss confirmed")
                return .unavailable

            case let .retainingTrigger(until):
                recordHDRRecoveryObservationIfNeeded(
                    screen: screen,
                    displayId: displayId,
                    recoveryState: recoveryState,
                    message: "Retained HDR trigger has not recovered",
                    minimumInterval: 5
                )
                guard now >= until else { return .unavailable }

                let retainedTriggerContext = hdrDiagnosticContext(
                    screen: screen,
                    displayId: displayId
                )
                hdrRecoverySummaries[displayId]?.beforeRecreation = "\(Date()): \(retainedTriggerContext)"
                recoveryState.hasRecreatedTriggerDuringOutage = true
                closeHDROverlay(displayId: displayId)
                BrightnessDiagnosticHistory.record(
                    "Retained HDR trigger did not recover display \(displayId); recreating it once; " +
                    retainedTriggerContext
                )
                notifyHDRCooldownEnded(displayId: displayId)
                recoveryState.hdrState = nil
                return beginHDREngagement(screen: screen, displayId: displayId)

            case let .waitingForHDR(until):
                recordHDRRecoveryObservationIfNeeded(
                    screen: screen,
                    displayId: displayId,
                    recoveryState: recoveryState,
                    message: "HDR engagement has not completed; " +
                        "\(max(0, Int(ceil(until.timeIntervalSince(now)))))s remaining"
                )
                guard now >= until else { return .unavailable }

                if recoveryState.hasRecreatedTriggerDuringOutage {
                    monitorUnavailableHDR(screen: screen, displayId: displayId)
                } else {
                    beginHDRRecovery(
                        screen: screen,
                        displayId: displayId,
                        reason: "initial HDR engagement timed out"
                    )
                }
                return .unavailable

            case .monitoringUnavailable:
                return .unavailable
            }
        }

        guard hdrIsReady(screen) else {
            restoreGammaUntilHDRReturns(displayId: displayId, gammaTable: gammaTable)
            recoveryState.resetHDR(to: .confirmingLoss(until: now.addingTimeInterval(hdrLossConfirmationDuration)))
            recordHDRRecovery(
                screen: screen,
                displayId: displayId,
                message: "Possible HDR loss; confirming for \(hdrLossConfirmationDuration)s with neutral gamma and retained trigger",
                newOutage: true
            )
            return .unavailable
        }

        let becameReady = !recoveryState.isHDRReady
        recoveryState.isHDRReady = true
        if becameReady {
            BrightnessDiagnosticHistory.record(
                "Display \(displayId) became HDR ready; max EDR \(String(format: "%.4f", screen.maximumExtendedDynamicRangeColorComponentValue))"
            )
        }
        return .ready(newlyEngaged: becameReady)
    }

    private func stabilizedHDRRecoveryAvailability(
        screen: NSScreen,
        displayId: CGDirectDisplayID,
        recoveryState: DisplayRecoveryState,
        now: Date
    ) -> HDRAvailability {
        guard let readySince = recoveryState.hdrReadySince else {
            recoveryState.hdrReadySince = now
            BrightnessDiagnosticHistory.record(
                "Observed HDR recovery candidate for display \(displayId); " +
                "waiting \(String(format: "%.1f", hdrRecoveryStabilizationDuration))s for stability; " +
                hdrDiagnosticContext(screen: screen, displayId: displayId)
            )
            return .unavailable
        }

        guard now.timeIntervalSince(readySince) >= hdrRecoveryStabilizationDuration else {
            return .unavailable
        }

        recordHDRRecovery(screen: screen, displayId: displayId, message: "Stable HDR recovered; resuming brightness")
        recoveryState.resetHDR(ready: true)
        notifyHDRCooldownEnded(displayId: displayId)
        return .ready(newlyEngaged: true)
    }

    private func beginHDRRecovery(
        screen: NSScreen,
        displayId: CGDirectDisplayID,
        reason: String,
        retryDelay: TimeInterval? = nil
    ) {
        let recoveryState = displayRecoveryState(for: displayId)
        let newOutage = recoveryState.hdrState == nil
        recoveryState.isHDRReady = false
        recoveryState.hdrReadySince = nil
        recoveryState.lastHDREngagementObservationDate = nil

        if recoveryState.hasRecreatedTriggerDuringOutage {
            monitorUnavailableHDR(screen: screen, displayId: displayId)
            return
        }

        let retentionDuration = retryDelay ?? hdrTriggerRetentionDuration
        recoveryState.hdrState = .retainingTrigger(
            until: Date().addingTimeInterval(retentionDuration)
        )
        notifyHDRCooldownBegan(
            displayId: displayId,
            cooldownSeconds: max(1, Int(ceil(retentionDuration)))
        )
        recordHDRRecovery(
            screen: screen, displayId: displayId,
            message: "\(reason); neutral gamma, retaining trigger for \(Int(ceil(retentionDuration)))s before one recreation",
            newOutage: newOutage
        )
    }

    private func monitorUnavailableHDR(screen: NSScreen, displayId: CGDirectDisplayID) {
        let state = displayRecoveryState(for: displayId)
        if case .monitoringUnavailable = state.hdrState { return }
        state.hdrState = .monitoringUnavailable
        notifyHDRCooldownEnded(displayId: displayId)
        let reason = "Display \(displayId) has not recovered HDR after retaining and recreating its trigger."
        recordHDRRecovery(screen: screen, displayId: displayId, message: reason + " Monitoring for recovery.")
        scheduleBrightnessFailurePrompt(reason: reason) { [weak self, weak state] in
            guard let self, let state, self.isEnabled,
                  self.displayRecoveryStates[displayId] === state,
                  CGDisplayIsAsleep(displayId) == 0,
                  case .monitoringUnavailable = state.hdrState else { return false }
            return true
        }
    }

    private func recordHDRRecovery(screen: NSScreen, displayId: CGDirectDisplayID, message: String, newOutage: Bool = false) {
        let context = hdrDiagnosticContext(screen: screen, displayId: displayId)
        let entry = "\(Date()): \(message); \(context)"
        if newOutage || hdrRecoverySummaries[displayId] == nil {
            hdrRecoverySummaries[displayId] = (entry, nil, entry)
        } else {
            hdrRecoverySummaries[displayId]?.latest = entry
        }
        BrightnessDiagnosticHistory.record("Display \(displayId): \(message); \(context)")
    }

    private func recordHDRRecoveryObservationIfNeeded(
        screen: NSScreen,
        displayId: CGDirectDisplayID,
        recoveryState: DisplayRecoveryState,
        message: String,
        minimumInterval: TimeInterval = 2
    ) {
        let now = Date()
        if recoveryState.lastHDREngagementObservationDate.map({
            now.timeIntervalSince($0) < minimumInterval
        }) ?? false {
            return
        }
        recoveryState.lastHDREngagementObservationDate = now
        BrightnessDiagnosticHistory.record(
            "\(message) for display \(displayId); " +
            hdrDiagnosticContext(screen: screen, displayId: displayId)
        )
    }

    private func hdrDiagnosticContext(
        screen: NSScreen,
        displayId: CGDirectDisplayID
    ) -> String {
        let currentEdr = screen.maximumExtendedDynamicRangeColorComponentValue
        let potentialEdr = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
        let referenceEdr = screen.maximumReferenceExtendedDynamicRangeColorComponentValue
        let foregroundApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unavailable"
        let presentationOptions = NSApplication.shared.currentSystemPresentationOptions
        let isFullScreen = presentationOptions.contains(.fullScreen)

        let overlayDescription: String
        if let window = overlayWindowControllers[displayId]?.window {
            let rendering = (window as? OverlayWindow)?.overlay?.renderingDiagnostics ?? "rendering unavailable"
            overlayDescription = "visible \(window.isVisible), occlusion-visible " +
                "\(window.occlusionState.contains(.visible)), frame \(window.frame), \(rendering)"
        } else {
            overlayDescription = "none"
        }

        return String(
            format: "current/potential/reference EDR %.4f/%.4f/%.4f, foreground %@, fullscreen %@, overlay %@",
            currentEdr,
            potentialEdr,
            referenceEdr,
            foregroundApp,
            isFullScreen ? "true" : "false",
            overlayDescription
        )
    }

    private func notifyHDRCooldownBegan(
        displayId: CGDirectDisplayID,
        cooldownSeconds: Int
    ) {
        NotificationCenter.default.post(
            name: .brightIntoshHDRCooldownDidBegin,
            object: nil,
            userInfo: [
                "cooldownSeconds": cooldownSeconds,
                "displayID": NSNumber(value: displayId),
            ]
        )
    }

    private func notifyHDRCooldownEnded(displayId: CGDirectDisplayID) {
        NotificationCenter.default.post(
            name: .brightIntoshHDRCooldownDidEnd,
            object: nil,
            userInfo: ["displayID": NSNumber(value: displayId)]
        )
    }

    private func restoreGammaUntilHDRReturns(
        displayId: CGDirectDisplayID,
        gammaTable: GammaTable
    ) {
        let state = fadeState(for: displayId)
        cancelUpwardGammaAdjustment(displayId: displayId)
        let needsRestore = state.task != nil ||
            state.targetFactor != nil ||
            abs(state.appliedFactor - 1.0) > gammaFactorEpsilon
        guard needsRestore else { return }

        state.task?.cancel()
        state.task = nil
        state.targetFactor = nil
        state.appliedFactor = 1.0
        applyGammaTable(gammaTable, displayId: displayId)
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

    private func handlePersistentGammaConflict(
        displayId: CGDirectDisplayID,
        recoveryDetails: String
    ) {
        guard gammaConflictDisplayIds.insert(displayId).inserted else { return }
        let reason = "Display \(displayId) repeatedly reset the gamma table after BrightIntosh applied it."
        captureFailureState(
            displayId: displayId,
            reason: reason,
            recoveryDetails: [recoveryDetails]
        )
        if let gammaTable = gammaTables[displayId] {
            applyGammaTable(gammaTable, displayId: displayId)
        }
        fadeStates[displayId]?.task?.cancel()
        fadeStates[displayId]?.upwardAdjustmentTask?.cancel()
        fadeStates.removeValue(forKey: displayId)
        displayRecoveryStates.removeValue(forKey: displayId)
        gammaTables.removeValue(forKey: displayId)
        notifyHDRCooldownEnded(displayId: displayId)
        closeHDROverlay(displayId: displayId)
        print("Persistent gamma conflict isolated to display \(displayId): \(reason)")
        BrightnessDiagnosticHistory.record(
            "Gamma conflict isolated to display \(displayId); other displays remain active: \(reason)"
        )
        scheduleBrightnessFailurePrompt(reason: reason) { [weak self] in
            self?.isEnabled == true && self?.gammaConflictDisplayIds.contains(displayId) == true &&
                self?.screenForDisplay(displayId) != nil && CGDisplayIsAsleep(displayId) == 0
        }
    }

    private func handleGammaCaptureFailure(displayId: CGDirectDisplayID) {
        let reason = "CGGetDisplayTransferByTable failed for display \(displayId)."
        guard gammaCaptureFailures[displayId] == nil else { return }
        gammaCaptureFailures[displayId] = reason
        fadeStates[displayId]?.task?.cancel()
        fadeStates[displayId]?.upwardAdjustmentTask?.cancel()
        fadeStates.removeValue(forKey: displayId)
        displayRecoveryStates.removeValue(forKey: displayId)
        notifyHDRCooldownEnded(displayId: displayId)
        closeHDROverlay(displayId: displayId)
        print("Gamma capture failure isolated to display \(displayId): \(reason)")
        BrightnessDiagnosticHistory.record(
            "Gamma capture failure isolated to display \(displayId); " +
            "other displays remain active and this display will be retried: \(reason)"
        )
        scheduleBrightnessFailurePrompt(reason: reason) { [weak self] in
            self?.isEnabled == true && self?.gammaCaptureFailures[displayId] != nil &&
                self?.screenForDisplay(displayId) != nil && CGDisplayIsAsleep(displayId) == 0
        }
    }

    private func captureFailureState(
        displayId: CGDirectDisplayID,
        reason: String,
        recoveryDetails: [String]
    ) {
        let maxEdr = screenForDisplay(displayId)?.maximumExtendedDynamicRangeColorComponentValue
        let fadeState = fadeStates[displayId]
        let recoveryState = displayRecoveryStates[displayId]
        lastFailureState = """
         - Reason: \(reason)
         - Display ID: \(displayId)
         - Increased brightness setting: \(BrightIntoshSettings.shared.brightintoshActive)
         - Technique enabled: \(isEnabled)
         - Max EDR: \(maxEdr.map { String(format: "%.4f", $0) } ?? "unavailable")
         - Display event timing: \(SupportReportContext.displayEventTiming())
         - Recovery details: \(recoveryDetails.joined(separator: "; "))
         - Consecutive gamma recovery count: \(recoveryState?.consecutiveGammaRecoveries ?? 0)
         - Gamma table: \(gammaTables[displayId].map(String.init(describing:)) ?? "none")
         - Fade applied factor: \(fadeState.map { String(format: "%.4f", $0.appliedFactor) } ?? "none")
         - Fade target factor: \(fadeState?.targetFactor.map { String(format: "%.4f", $0) } ?? "none")
         - Fade active: \(fadeState?.task != nil)
         - HDR ready: \(recoveryState?.isHDRReady ?? false)
         - Overlay display IDs: \(overlayWindowControllers.keys.sorted())
        """
    }

    func appendSupportDiagnostics(to report: inout String) {
        let hdrReadyDisplayIds = displayRecoveryStates.compactMap { displayId, state in
            state.isHDRReady ? displayId : nil
        }.sorted()
        let consecutiveGammaRecoveries = displayRecoveryStates.reduce(into: [CGDirectDisplayID: Int]()) {
            if $1.value.consecutiveGammaRecoveries > 0 {
                $0[$1.key] = $1.value.consecutiveGammaRecoveries
            }
        }
        let activeHDRRecoveryStates = displayRecoveryStates.compactMap { displayId, state in
            state.hdrState.map { (displayId, $0) }
        }.sorted { $0.0 < $1.0 }
        let pendingUpwardGammaDisplayIds = fadeStates.compactMap { displayId, state in
            state.upwardAdjustmentTask != nil ? displayId : nil
        }.sorted()
        let overlayRenderingDiagnostics = overlayWindowControllers.map { displayId, controller in
            let rendering = (controller.window as? OverlayWindow)?.overlay?.renderingDiagnostics
                ?? "rendering unavailable"
            return "\(displayId): \(rendering)"
        }.sorted()

        if let lastFailureState {
            report += "Gamma state at failure:\n\(lastFailureState)\n"
        }
        report += "Gamma technique:\n"
        report += " - Technique enabled: \(isEnabled)\n"
        report += " - Overlay display IDs: \(overlayWindowControllers.keys.sorted())\n"
        report += " - Gamma tables: \(gammaTables)\n"
        report += " - Fading display IDs: \(fadeStates.keys.sorted())\n"
        report += " - Pending upward gamma display IDs: \(pendingUpwardGammaDisplayIds)\n"
        report += " - HDR-ready display IDs: \(hdrReadyDisplayIds)\n"
        for displayId in hdrRecoverySummaries.keys.sorted() {
            guard let summary = hdrRecoverySummaries[displayId] else { continue }
            report += " - Last HDR outage on display \(displayId):\n   Onset: \(summary.onset)\n   Before recreation: \(summary.beforeRecreation ?? "not recreated")\n   Latest: \(summary.latest)\n"
        }
        report += " - Overlay rendering: \(overlayRenderingDiagnostics)\n"
        if activeHDRRecoveryStates.isEmpty {
            report += " - HDR recovery states: none\n"
        } else {
            report += " - HDR recovery states:\n"
            for (displayId, state) in activeHDRRecoveryStates {
                report += "   · display \(displayId): \(hdrRecoveryDescription(state))\n"
            }
        }
        report += " - HDR loss confirmation: \(String(format: "%.1f", hdrLossConfirmationDuration))s\n"
        report += " - HDR recovery stabilization: \(String(format: "%.1f", hdrRecoveryStabilizationDuration))s\n"
        report += " - HDR trigger retention before recreation: \(Int(hdrTriggerRetentionDuration))s\n"
        report += " - Consecutive gamma recovery counts: \(consecutiveGammaRecoveries)\n"
        report += " - Gamma capture failures: \(gammaCaptureFailures)\n"
        report += " - Gamma-conflict isolated displays: \(gammaConflictDisplayIds.sorted())\n"
        report += " - Gamma-conflict grace remaining: \(max(0, Int(ceil(gammaConflictChecksAllowedAfter.timeIntervalSinceNow))))s\n"
        report += " - Integrity poll active: \(integrityPollTask != nil)\n"
    }

    private func hdrRecoveryDescription(_ state: HDRRecoveryState) -> String {
        switch state {
        case .waitingForDisplayWake:
            return "waiting for display wake"
        case let .confirmingLoss(until):
            return "confirming HDR loss, \(max(0, Int(ceil(until.timeIntervalSinceNow))))s remaining"
        case let .waitingForHDR(until):
            return "waiting for HDR, \(max(0, Int(ceil(until.timeIntervalSinceNow))))s remaining"
        case let .retainingTrigger(until):
            return "retaining HDR trigger before one recreation, \(max(0, Int(ceil(until.timeIntervalSinceNow))))s remaining"
        case .monitoringUnavailable:
            return "monitoring unavailable HDR without disabling brightness"
        }
    }
}
