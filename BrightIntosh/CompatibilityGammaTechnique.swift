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

    nonisolated private static let colorStateLock = NSLock()
    private let gammaFadeDuration: TimeInterval = 0.2
    private let gammaFadeFrameInterval: Duration = .milliseconds(16)
    private let gammaFactorEpsilon: Float = 0.001

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

        for controller in overlayWindowControllers.values {
            guard let displayId = controller.screen.displayId,
                  let gammaTable = gammaTables[displayId] else {
                continue
            }

            let (referenceEdr, maxScreenBrightness) = getScreenRefGamma(controller.screen)
            let factor = Self.gammaFactor(
                userBrightness: userBrightness,
                maxScreenBrightness: maxScreenBrightness,
                referenceEdr: referenceEdr,
                currentEdr: controller.screen.maximumExtendedDynamicRangeColorComponentValue
            )

            fadeGammaFactor(displayId: displayId, gammaTable: gammaTable, targetFactor: factor)
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
                controller.reposition(screen: screen)
            } else {
                enableScreen(screen: screen)
            }
        }

        adjustBrightness()
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
        cancelAllFades()

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
        if !targetChanged, state.task != nil {
            return
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

    func appendSupportDiagnostics(to report: inout String) {
        report += "Compatibility gamma technique:\n"
        report += " - Technique enabled: \(isEnabled)\n"
        report += " - Overlay display IDs: \(overlayWindowControllers.keys.sorted())\n"
        report += " - Gamma tables: \(gammaTables)\n"
        report += " - Fading display IDs: \(fadeStates.keys.sorted())\n"
    }
}
