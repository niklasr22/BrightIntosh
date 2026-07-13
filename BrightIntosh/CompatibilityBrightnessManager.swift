//
//  CompatibilityBrightnessManager.swift
//  BrightIntosh
//

import Cocoa
import Combine
import CoreGraphics

@MainActor
final class CompatibilityBrightnessManager: BrightnessManaging {
    private struct DisplaySnapshot {
        let screens: [NSScreen]
        let targetScreens: [NSScreen]

        @MainActor
        static func current() -> DisplaySnapshot {
            DisplaySnapshot(screens: NSScreen.screens, targetScreens: getXDRDisplays())
        }

        var screenFrames: [CGDirectDisplayID: NSRect] {
            Dictionary(uniqueKeysWithValues: screens.compactMap { screen in
                screen.displayId.map { ($0, screen.frame) }
            })
        }

        var targetDisplayIds: Set<CGDirectDisplayID> {
            Set(targetScreens.compactMap(\.displayId))
        }

        func topologyDiffers(from other: DisplaySnapshot) -> Bool {
            screenFrames != other.screenFrames ||
                targetDisplayIds != other.targetDisplayIds
        }

        func lostBuiltInDisplay(comparedTo other: DisplaySnapshot) -> Bool {
            other.screens.contains(where: { isBuiltInScreen(screen: $0) }) &&
                !screens.contains(where: { isBuiltInScreen(screen: $0) })
        }
    }

    private let brightnessTechnique = CompatibilityGammaTechnique()
    private let displayStabilizationDelay: Duration = .seconds(5)

    private var displays = DisplaySnapshot.current()
    private var stabilizationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    nonisolated private static let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = {
        displayId,
        flags,
        userInfo in
        guard let userInfo else {
            print("Display reconfiguration callback ignored without manager context: \(flags)")
            return
        }

        let manager = Unmanaged<CompatibilityBrightnessManager>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        if flags.contains(.beginConfigurationFlag) {
            // This callback is the earliest warning that a display may disappear.
            CompatibilityGammaTechnique.restoreSystemColorState()
            Task { @MainActor in
                manager.suspend(
                    reason: "display \(displayId) reconfiguration began (flags: \(flags))"
                )
            }
        } else {
            Task { @MainActor in
                manager.scheduleActivationAfterDisplayStabilizes(
                    reason: "display reconfiguration ended"
                )
            }
        }
    }

    init() {
        registerObservers()
        registerSettingsListeners()
        registerDisplayReconfigurationCallback()

        if BrightIntoshSettings.shared.brightintoshActive {
            activateImmediately(reason: "launch")
        }

        print("Initialized compatibility brightness manager")
    }

    deinit {
        stabilizationTask?.cancel()
        CGDisplayRemoveReconfigurationCallback(
            Self.displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)

        let brightnessTechnique = brightnessTechnique
        Task { @MainActor in
            brightnessTechnique.reset(reason: "manager deinitialized")
        }
    }

    private var activationRequested: Bool {
        BrightIntoshSettings.shared.brightintoshActive
    }

    private func registerObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
    }

    private func registerSettingsListeners() {
        Authorizer.shared.$status.sink { status in
            if status == .unauthorized && BrightIntoshSettings.shared.brightintoshActive {
                BrightIntoshSettings.shared.brightintoshActive = false
            }
        }.store(in: &cancellables)

        BrightIntoshSettings.shared.addListener(setting: "brightintoshActive") {
            if self.activationRequested {
                self.activateImmediately(reason: "enabled by user")
            } else {
                self.deactivate(reason: "disabled by user")
            }
        }

        BrightIntoshSettings.shared.addListener(setting: "brightIntoshOnlyOnBuiltIn") {
            self.reconcileDisplaySelection()
        }

        BrightIntoshSettings.shared.addListener(setting: "disableWhenLidClosed") {
            self.reconcileDisplaySelection()
        }

        BrightIntoshSettings.shared.addListener(setting: "fineGrainedBrightnessControl") {
            self.adjustBrightness()
        }

        BrightIntoshSettings.shared.addListener(setting: "brightness") {
            self.adjustBrightness()
        }
    }

    private func registerDisplayReconfigurationCallback() {
        let error = CGDisplayRegisterReconfigurationCallback(
            Self.displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        if error != .success {
            print("Could not register display reconfiguration callback: \(error)")
        }
    }

    @objc private func screenParametersDidChange() {
        let updatedDisplays = DisplaySnapshot.current()
        let previousDisplays = displays
        displays = updatedDisplays

        if shouldDisableForClosedLid(
            current: updatedDisplays,
            previous: previousDisplays
        ) {
            disableForClosedLid()
            return
        }

        guard activationRequested else {
            return
        }

        if updatedDisplays.topologyDiffers(from: previousDisplays) {
            suspendAndScheduleActivation(reason: "display setup changed")
        } else if brightnessTechnique.isEnabled {
            // Screen parameter notifications also cover native brightness changes.
            brightnessTechnique.adjustBrightness()
        }
    }

    @objc private func systemDidWake() {
        guard activationRequested else {
            return
        }

        displays = DisplaySnapshot.current()
        if shouldDisableForClosedLid(current: displays) {
            disableForClosedLid()
            return
        }

        suspendAndScheduleActivation(reason: "system woke")
    }

    @objc private func screensDidSleep() {
        suspend(reason: "screens slept")
    }

    @objc private func systemWillSleep() {
        suspend(reason: "system will sleep")
    }

    private func activateImmediately(reason: String) {
        cancelScheduledActivation()

        guard activationRequested else {
            deactivate(reason: "activation no longer requested")
            return
        }

        guard Authorizer.shared.isAllowed() else {
            BrightIntoshSettings.shared.brightintoshActive = false
            return
        }

        displays = DisplaySnapshot.current()

        if shouldDisableForClosedLid(current: displays) {
            disableForClosedLid()
            return
        }

        guard !displays.targetScreens.isEmpty else {
            deactivate(reason: "no compatible displays")
            return
        }

        print("Activating compatibility brightness: \(reason)")
        brightnessTechnique.enable(screens: displays.targetScreens)
    }

    private func deactivate(reason: String) {
        cancelScheduledActivation()
        if brightnessTechnique.isEnabled {
            brightnessTechnique.reset(reason: reason)
        }
    }

    private func suspend(reason: String) {
        cancelScheduledActivation()
        brightnessTechnique.reset(reason: reason)
    }

    private func suspendAndScheduleActivation(reason: String) {
        brightnessTechnique.reset(reason: reason)
        scheduleActivationAfterDisplayStabilizes(reason: reason)
    }

    private func scheduleActivationAfterDisplayStabilizes(reason: String) {
        cancelScheduledActivation()

        guard activationRequested else {
            return
        }

        print("Waiting \(displayStabilizationDelay) before activating compatibility brightness: \(reason)")

        stabilizationTask = Task { @MainActor in
            try? await Task.sleep(for: self.displayStabilizationDelay)
            guard !Task.isCancelled else {
                return
            }

            self.stabilizationTask = nil
            self.activateImmediately(reason: "display state stabilized after \(reason)")
        }
    }

    private func cancelScheduledActivation() {
        stabilizationTask?.cancel()
        stabilizationTask = nil
    }

    private func reconcileDisplaySelection() {
        let previousDisplays = displays
        displays = DisplaySnapshot.current()

        if shouldDisableForClosedLid(
            current: displays,
            previous: previousDisplays
        ) {
            disableForClosedLid()
            return
        }

        guard activationRequested else {
            return
        }

        if brightnessTechnique.isEnabled {
            guard !displays.targetScreens.isEmpty else {
                deactivate(reason: "no compatible displays selected")
                return
            }
            brightnessTechnique.screenUpdate(screens: displays.targetScreens)
        } else if stabilizationTask == nil {
            activateImmediately(reason: "display preference changed")
        }
    }

    private func adjustBrightness() {
        guard activationRequested,
              brightnessTechnique.isEnabled else {
            return
        }
        brightnessTechnique.adjustBrightnessValue()
    }

    private func shouldDisableForClosedLid(
        current: DisplaySnapshot,
        previous: DisplaySnapshot? = nil
    ) -> Bool {
        guard BrightIntoshSettings.shared.disableWhenLidClosed else {
            return false
        }

        if let previous, current.lostBuiltInDisplay(comparedTo: previous) {
            return true
        }

        if let clamshellClosed = isClamshellClosed() {
            return clamshellClosed
        }

        return !current.screens.isEmpty &&
            !current.screens.contains(where: { isBuiltInScreen(screen: $0) })
    }

    private func disableForClosedLid() {
        deactivate(reason: "MacBook lid closed")
        if BrightIntoshSettings.shared.brightintoshActive {
            BrightIntoshSettings.shared.brightintoshActive = false
        }
    }

    func appendSupportDiagnostics(to report: inout String) {
        let state = stabilizationTask != nil
            ? "stabilizing"
            : brightnessTechnique.isEnabled ? "active" : "inactive"
        report += "Compatibility brightness manager:\n"
        report += " - State: \(state)\n"
        report += " - Increased brightness setting: \(activationRequested)\n"
        report += " - Active displays: \(displays.screenFrames.keys.sorted())\n"
        report += " - Target displays: \(displays.targetDisplayIds.sorted())\n"
        brightnessTechnique.appendSupportDiagnostics(to: &report)
    }
}
