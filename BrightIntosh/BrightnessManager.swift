//
//  BrightnessManager.swift
//  BrightIntosh
//

import Cocoa
import Combine
import CoreGraphics

private extension Notification.Name {
    static let screenSaverDidStart = Notification.Name("com.apple.screensaver.didstart")
    static let screenSaverDidStop = Notification.Name("com.apple.screensaver.didstop")
}

extension NSScreen {
    var displayId: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
}
@MainActor
protocol BrightnessManaging: AnyObject {
    func appendSupportDiagnostics(to report: inout String)
    func protectedDataWillBecomeUnavailable()
    func protectedDataDidBecomeAvailable()
}

@MainActor
final class BrightnessManager: BrightnessManaging {
    private enum PresentationInactivityReason: String, Hashable {
        case protectedDataUnavailable = "protected data unavailable"
        case screenSaver = "screen saver active"
        case sessionInactive = "session inactive"
    }

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

    private var brightnessTechnique: BrightnessTechnique
    private let displayStabilizationDelay: Duration = .seconds(5)

    private var displays = DisplaySnapshot.current()
    private var stabilizationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var lastScreenParameterDiagnosticDate: Date?
    private var presentationInactivityReasons: Set<PresentationInactivityReason> = []

    nonisolated private static let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = {
        displayId,
        flags,
        userInfo in
        guard let userInfo else {
            print("Display reconfiguration callback ignored without manager context: \(flags)")
            return
        }

        let manager = Unmanaged<BrightnessManager>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        if flags.contains(.beginConfigurationFlag) {
            // This callback is the earliest warning that a display may disappear.
            GammaTechnique.restoreSystemColorState()
            Task { @MainActor in
                manager.recordDisplaySetupChange(
                    reason: "display \(displayId) reconfiguration began (flags: \(flags))"
                )
                manager.suspend(
                    reason: "display \(displayId) reconfiguration began (flags: \(flags))"
                )
            }
        } else {
            Task { @MainActor in
                manager.recordDisplaySetupChange(reason: "display reconfiguration ended")
                manager.scheduleActivationAfterDisplayStabilizes(
                    reason: "display reconfiguration ended"
                )
            }
        }
    }

    init() {
        brightnessTechnique = Self.makeBrightnessTechnique()
        BrightnessDiagnosticHistory.record(
            "Manager initialized; backend \(Self.backendName), displays \(Self.displaySummary(DisplaySnapshot.current()))"
        )
        registerObservers()
        synchronizeProtectedDataAvailability()
        registerSettingsListeners()
        registerDisplayReconfigurationCallback()

        if BrightIntoshSettings.shared.brightintoshActive {
            activateImmediately(reason: "launch")
        }

        print("Initialized brightness manager")
    }

    deinit {
        let brightnessTechnique = brightnessTechnique
        stabilizationTask?.cancel()
        CGDisplayRemoveReconfigurationCallback(
            Self.displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)

        Task { @MainActor in
            brightnessTechnique.disable()
        }
    }

    private var activationRequested: Bool {
        BrightIntoshSettings.shared.brightintoshActive
    }

    private static var backendName: String {
        BrightIntoshSettings.shared.useAlternateBrightnessBackend ? "alternate" : "gamma"
    }

    private func registerObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(
            self,
            selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(screensDidSleep(_:)),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(screensDidWake(_:)),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(systemWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(sessionDidResignActive(_:)),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        let distributedNotifications = DistributedNotificationCenter.default()
        distributedNotifications.addObserver(
            self,
            selector: #selector(screenSaverDidStart(_:)),
            name: .screenSaverDidStart,
            object: nil
        )
        distributedNotifications.addObserver(
            self,
            selector: #selector(screenSaverDidStop(_:)),
            name: .screenSaverDidStop,
            object: nil
        )
    }

    private func synchronizeProtectedDataAvailability() {
        guard !NSApplication.shared.isProtectedDataAvailable else {
            return
        }
        presentationInactivityReasons.insert(.protectedDataUnavailable)
        BrightnessDiagnosticHistory.record(
            "Presentation initially inactive: \(presentationInactivityDescription)"
        )
    }

    private func registerSettingsListeners() {
        Authorizer.shared.$status.sink { status in
            if status == .unauthorized && BrightIntoshSettings.shared.brightintoshActive {
                BrightIntoshSettings.shared.setBrightintoshActive(
                    false,
                    reason: "authorization revoked"
                )
            }
        }.store(in: &cancellables)

        BrightIntoshSettings.shared.addListener(setting: "brightintoshActive") {
            let reason = BrightIntoshSettings.shared.brightintoshActiveChangeReason ??
                (self.activationRequested ? "setting enabled" : "setting disabled")
            if self.activationRequested {
                self.activateImmediately(reason: reason)
            } else {
                self.deactivate(reason: reason)
            }
        }

        BrightIntoshSettings.shared.addListener(setting: "brightIntoshOnlyOnBuiltIn") {
            self.reconcileDisplaySelection()
        }

        BrightIntoshSettings.shared.addListener(setting: "disableWhenLidClosed") {
            self.reconcileDisplaySelection()
        }

        BrightIntoshSettings.shared.addListener(setting: "useAlternateBrightnessBackend") {
            self.switchBrightnessTechnique()
        }

        BrightIntoshSettings.shared.addListener(setting: "waitForHDRBeforeIncreasingBrightness") {
            if BrightIntoshSettings.shared.useAlternateBrightnessBackend {
                self.restartBrightnessTechnique(reason: "HDR preference changed")
            }
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

    @objc private func screenParametersDidChange(_ notification: Notification) {
        let updatedDisplays = DisplaySnapshot.current()
        let previousDisplays = displays
        displays = updatedDisplays
        let topologyChanged = updatedDisplays.topologyDiffers(from: previousDisplays)

        if topologyChanged {
            recordDisplaySetupChange(reason: "screen parameters changed the display setup")
        }

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

        if topologyChanged {
            suspendAndScheduleActivation(reason: "display setup changed")
        } else if brightnessTechnique.isEnabled {
            // Screen parameter notifications also cover native brightness changes.
            let now = Date()
            if lastScreenParameterDiagnosticDate.map({
                now.timeIntervalSince($0) >= 1
            }) ?? true {
                lastScreenParameterDiagnosticDate = now
                BrightnessDiagnosticHistory.record(
                    "Screen parameters changed without a topology change; " +
                    Self.edrSummary(updatedDisplays)
                )
            }
            brightnessTechnique.updateBrightness(reason: .displayParametersChanged)
        }
    }

    @objc private func systemDidWake(_ notification: Notification) {
        SupportReportContext.lastSystemWake = Date()
        BrightnessDiagnosticHistory.record("System wake notification received")
        reactivateAfterWake(reason: "system woke")
    }

    @objc private func screensDidWake(_ notification: Notification) {
        BrightnessDiagnosticHistory.record("Screens wake notification received")
        reactivateAfterWake(reason: "screens woke")
    }

    private func reactivateAfterWake(reason: String) {
        guard activationRequested else {
            return
        }

        guard presentationInactivityReasons.isEmpty else {
            BrightnessDiagnosticHistory.record(
                "Deferring activation after \(reason); presentation remains inactive: " +
                presentationInactivityDescription
            )
            return
        }

        displays = DisplaySnapshot.current()
        if shouldDisableForClosedLid(current: displays) {
            disableForClosedLid()
            return
        }

        suspendAndScheduleActivation(reason: reason)
    }

    @objc private func screensDidSleep(_ notification: Notification) {
        BrightnessDiagnosticHistory.record("Screens sleep notification received")
        suspend(reason: "screens slept")
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        BrightnessDiagnosticHistory.record("System will sleep notification received")
        suspend(reason: "system will sleep")
    }

    func protectedDataWillBecomeUnavailable() {
        presentationDidBecomeInactive(.protectedDataUnavailable)
    }

    func protectedDataDidBecomeAvailable() {
        presentationDidBecomeActive(.protectedDataUnavailable)
    }

    @objc private func screenSaverDidStart(_ notification: Notification) {
        presentationDidBecomeInactive(.screenSaver)
    }

    @objc private func screenSaverDidStop(_ notification: Notification) {
        presentationDidBecomeActive(.screenSaver)
    }

    @objc private func sessionDidResignActive(_ notification: Notification) {
        presentationDidBecomeInactive(.sessionInactive)
    }

    @objc private func sessionDidBecomeActive(_ notification: Notification) {
        presentationDidBecomeActive(.sessionInactive)
    }

    private func presentationDidBecomeInactive(_ reason: PresentationInactivityReason) {
        guard presentationInactivityReasons.insert(reason).inserted else {
            return
        }

        BrightnessDiagnosticHistory.record(
            "Presentation became inactive: \(reason.rawValue); active reasons: " +
            presentationInactivityDescription
        )
        suspend(reason: reason.rawValue)
    }

    private func presentationDidBecomeActive(_ reason: PresentationInactivityReason) {
        guard presentationInactivityReasons.remove(reason) != nil else {
            return
        }

        BrightnessDiagnosticHistory.record(
            "Presentation inactivity ended: \(reason.rawValue); remaining reasons: " +
            presentationInactivityDescription
        )
        guard presentationInactivityReasons.isEmpty, activationRequested else {
            return
        }

        displays = DisplaySnapshot.current()
        if shouldDisableForClosedLid(current: displays) {
            disableForClosedLid()
            return
        }

        suspendAndScheduleActivation(reason: "presentation became active")
    }

    private var presentationInactivityDescription: String {
        let reasons = presentationInactivityReasons.map(\.rawValue).sorted()
        return reasons.isEmpty ? "none" : reasons.joined(separator: ", ")
    }

    private func activateImmediately(reason: String) {
        cancelScheduledActivation()

        guard activationRequested else {
            deactivate(reason: "activation no longer requested")
            return
        }

        guard presentationInactivityReasons.isEmpty else {
            BrightnessDiagnosticHistory.record(
                "Activation deferred while presentation is inactive: " +
                presentationInactivityDescription
            )
            return
        }

        guard Authorizer.shared.isAllowed() else {
            BrightIntoshSettings.shared.setBrightintoshActive(
                false,
                reason: "authorization unavailable"
            )
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

        print("Activating brightness: \(reason)")
        BrightnessDiagnosticHistory.record(
            "Activating \(Self.backendName) technique: \(reason); targets \(displays.targetDisplayIds.sorted())"
        )
        brightnessTechnique.enable(screens: displays.targetScreens)
    }

    private func deactivate(reason: String) {
        cancelScheduledActivation()
        if brightnessTechnique.isEnabled {
            print("Disabling brightness: \(reason)")
            BrightnessDiagnosticHistory.record("Disabling brightness: \(reason)")
            brightnessTechnique.disable()
        }
    }

    private func suspend(reason: String) {
        cancelScheduledActivation()
        if brightnessTechnique.isEnabled {
            print("Suspending brightness: \(reason)")
            BrightnessDiagnosticHistory.record("Suspending brightness: \(reason)")
            brightnessTechnique.disable()
        }
    }

    private func suspendAndScheduleActivation(reason: String) {
        if brightnessTechnique.isEnabled {
            print("Suspending brightness before stabilization: \(reason)")
            BrightnessDiagnosticHistory.record("Suspending before display stabilization: \(reason)")
            brightnessTechnique.disable()
        }
        scheduleActivationAfterDisplayStabilizes(reason: reason)
    }

    private func scheduleActivationAfterDisplayStabilizes(reason: String) {
        cancelScheduledActivation()

        guard activationRequested, presentationInactivityReasons.isEmpty else {
            return
        }

        print("Waiting \(displayStabilizationDelay) before activating brightness: \(reason)")
        BrightnessDiagnosticHistory.record("Scheduled display stabilization: \(reason)")

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
        if stabilizationTask != nil {
            BrightnessDiagnosticHistory.record("Cancelled pending display stabilization")
        }
        stabilizationTask?.cancel()
        stabilizationTask = nil
    }

    private func recordDisplaySetupChange(reason: String) {
        SupportReportContext.lastDisplaySetupChange = (Date(), reason)
        BrightnessDiagnosticHistory.record(
            "Display setup event: \(reason); \(Self.displaySummary(DisplaySnapshot.current()))"
        )
    }

    private static func displaySummary(_ snapshot: DisplaySnapshot) -> String {
        let screenFrames = snapshot.screenFrames
        let frames = screenFrames.keys.sorted().map {
            "\($0)=\(screenFrames[$0]!)"
        }.joined(separator: ", ")
        return "screens [\(frames)], targets \(snapshot.targetDisplayIds.sorted())"
    }

    private static func edrSummary(_ snapshot: DisplaySnapshot) -> String {
        let values = snapshot.screens.compactMap { screen -> String? in
            guard let displayId = screen.displayId else { return nil }
            return "\(displayId)=\(String(format: "%.4f", screen.maximumExtendedDynamicRangeColorComponentValue))"
        }.sorted()
        return "max EDR [\(values.joined(separator: ", "))]"
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
        brightnessTechnique.updateBrightness(reason: .brightnessSettingChanged)
    }

    private static func makeBrightnessTechnique() -> BrightnessTechnique {
        BrightIntoshSettings.shared.useAlternateBrightnessBackend
            ? MultiplyingOverlayTechnique()
            : GammaTechnique()
    }

    private func switchBrightnessTechnique() {
        cancelScheduledActivation()
        if brightnessTechnique.isEnabled {
            brightnessTechnique.disable()
        }
        brightnessTechnique = Self.makeBrightnessTechnique()
        print("Selected \(BrightIntoshSettings.shared.useAlternateBrightnessBackend ? "alternate" : "gamma") brightness backend")
        BrightnessDiagnosticHistory.record("Selected \(Self.backendName) brightness backend")

        if activationRequested {
            activateImmediately(reason: "brightness backend changed")
        }
    }

    private func restartBrightnessTechnique(reason: String) {
        guard activationRequested else {
            return
        }
        if brightnessTechnique.isEnabled {
            brightnessTechnique.disable()
        }
        activateImmediately(reason: reason)
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
            BrightIntoshSettings.shared.setBrightintoshActive(
                false,
                reason: "MacBook lid closed"
            )
        }
    }

    func appendSupportDiagnostics(to report: inout String) {
        let state: String
        if stabilizationTask != nil {
            state = "stabilizing"
        } else if brightnessTechnique.isEnabled {
            state = "active"
        } else if presentationInactivityReasons.isEmpty {
            state = "inactive"
        } else {
            state = "suspended"
        }
        report += "Brightness manager:\n"
        report += " - State: \(state)\n"
        report += " - Increased brightness setting: \(activationRequested)\n"
        report += " - Presentation inactivity: \(presentationInactivityDescription)\n"
        report += " - Active technique: \(String(describing: type(of: brightnessTechnique)))\n"
        report += " - Active displays: \(displays.screenFrames.keys.sorted())\n"
        report += " - Target displays: \(displays.targetDisplayIds.sorted())\n"
        report += " - Display event timing: \(SupportReportContext.displayEventTiming())\n"
        BrightnessDiagnosticHistory.append(to: &report)
        if let gammaTechnique = brightnessTechnique as? GammaTechnique {
            gammaTechnique.appendSupportDiagnostics(to: &report)
        } else if let hdrTechnique = brightnessTechnique as? MultiplyingOverlayTechnique {
            hdrTechnique.appendHDRSupportDiagnostics(to: &report)
        }
    }
}
