//
//  ScreenHelperMain.swift
//  BrightIntoshScreenHelper
//

import Cocoa
import OSLog

private let screenHelperLogger = Logger(
    subsystem: "BrightIntoshScreenHelper",
    category: "Main"
)

@main
enum ScreenHelperMain {
    static func main() {
        ProcessInfo.processInfo.disableAutomaticTermination("BrightIntosh screen HDR helper")
        
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let delegate = ScreenHelperAppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class ScreenHelperAppDelegate: NSObject, NSApplicationDelegate {
    
    private var technique: SingleDisplayGammaTechnique?
    private var launchDistributedObserver: NSObjectProtocol?
    private var brightnessSuiteDistributedObserver: NSObjectProtocol?
    private var activeSuiteDistributedObserver: NSObjectProtocol?
    private var crossProcessObserversRegistered = false
    
    private var screen: CGDirectDisplayID = 0
    
    private var defaultsSuite = UserDefaults(suiteName: defaultsSuiteName)!
    
    
    var activeObserver: NSKeyValueObservation?
    var brightnessObserver: NSKeyValueObservation?
    var helpersObserver: NSKeyValueObservation?
    var programsObserver: NSKeyValueObservation?
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        activeObserver = defaultsSuite.observe(\.active, options: [.new], changeHandler: { (defaults, change) in
            Task { @MainActor in
                if let newValue = change.newValue, !newValue {
                    screenHelperLogger.info("BrightIntosh got disabled, terminating helper for \(self.screen, privacy: .public). PID \(ProcessInfo.processInfo.processIdentifier, privacy: .public)")
                    NSApplication.shared.terminate(nil)
                }
            }
        })
        brightnessObserver = defaultsSuite.observe(\.brightness, options: [.new], changeHandler: { (defaults, change) in
            screenHelperLogger.info("BrightIntosh brightness change received by \(self.screen, privacy: .public)")
            Task { @MainActor in
                if let newValue = change.newValue {
                    self.technique?.adjustBrightness()
                }
            }
        })
        helpersObserver = defaultsSuite.observe(\.helpers, options: [.initial, .new], changeHandler: { (defaults, change) in
            screenHelperLogger.info("BrightIntosh received helper info.")
            guard let newValue = change.newValue, let helperInfo = newValue else {
                return
            }
            let helper = helperInfo.split(separator: ",").first(where: {$0.hasPrefix("\(ProcessInfo.processInfo.processIdentifier):")})
            
            guard let screenIdStr = helper?.split(separator: ":").last, let screenId = UInt32(screenIdStr) else {
                return
            }
            Task { @MainActor in
                self.screen = screenId
                self.finishLaunch(displayId: self.screen, brightness: self.defaultsSuite.brightness)
            }
        })
        
        
        programsObserver = NSWorkspace.shared.observe(\.runningApplications, changeHandler: { (defaults, change) in
            let deBundleIds = NSWorkspace.shared.runningApplications.map({ $0.bundleIdentifier ?? "n/a" }).filter({ $0.hasPrefix("de") }).joined(separator: ",")
            screenHelperLogger.info("Running programs updated \(deBundleIds, privacy: .public)")
            if !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "de.brightintosh.app" }) {
                screenHelperLogger.info("Helper got orphaned, terminating. PID: \(ProcessInfo.processInfo.processIdentifier, privacy: .public)")
                
                Task { @MainActor in
                    NSApp.terminate(nil)
                }
            }
        })
        
        screenHelperLogger.info("Running programs initial \(String(describing: NSWorkspace.shared.runningApplications), privacy: .public)")
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(15))
            guard self.technique == nil else {
                return
            }
            screenHelperLogger.info("BrightIntosh Helper received no target, terminating now.")
            NSApp.terminate(nil)
        }
        screenHelperLogger.info("BrightIntosh Helper launched waiting for target screen. \(String(describing: self.defaultsSuite.helpers), privacy: .public)")
    }
    
    private func finishLaunch(displayId: CGDirectDisplayID, brightness: Float) {
        screenHelperLogger.info("BrightIntoshScreenHelper: display \(UInt32(displayId), privacy: .public) brightness \(Double(brightness), privacy: .public)")
        let tech = SingleDisplayGammaTechnique(displayId: displayId, initialUserBrightness: brightness)
        tech.refreshUserBrightnessFromSuite()
        technique = tech
        tech.enable()
        
        screen = displayId
        
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ display, flags, userInfo in
            guard let userInfo = userInfo else { return }
            
            let appDelegate = Unmanaged<ScreenHelperAppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
            
            Task { @MainActor in
                appDelegate.displayReconfigured(display: display, flags: flags)
            }
        }, selfPointer)
    }
    
    @MainActor
    func displayReconfigured(display: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        if flags.contains(.removeFlag) || flags.contains(.disabledFlag), display == self.screen {
            screenHelperLogger.info("Terminating helper because the screen was removed \(ProcessInfo.processInfo.processIdentifier, privacy: .public)")
            NSApp.terminate(nil)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        technique?.disable()
    }
    
    
}
