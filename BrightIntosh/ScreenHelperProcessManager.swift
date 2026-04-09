//
//  ScreenHelperProcessManager.swift
//  BrightIntosh
//
//  Launches one BrightIntoshScreenHelper.app instance per XDR display via Launch Services
//  (NSWorkspace.openApplication). Spawning the helper executable with Process() from a sandboxed
//  parent prevents the child’s App Sandbox from applying and crashes in _libsecinit_appsandbox
//  (SYSCALL_SET_USERLAND_PROFILE).
//
//  Display id and initial brightness are published after `openApplication` returns, keyed by the
//  helper’s PID (sandbox strips custom environment on embedded helper launch).
//

import Cocoa
import Foundation

@MainActor
final class ScreenHelperProcessManager {
    
    private var runningByDisplay: [CGDirectDisplayID: NSRunningApplication] = [:]
    private var pendingLaunchDisplayIds: Set<CGDirectDisplayID> = []
    private var abortLaunchDisplayIds: Set<CGDirectDisplayID> = []
    private var xdrScreens: [NSScreen] = []
    
    private var applicationsObserver: NSKeyValueObservation?
    
    init() {
        applicationsObserver = NSWorkspace.shared.observe(\.runningApplications, options: [.initial, .new], changeHandler: self.runningAppsChanged)
    }
    
    private nonisolated func runningAppsChanged(_ workspace: NSWorkspace, _ change: NSKeyValueObservedChange<[NSRunningApplication]>) {
        Task { @MainActor in
            let updatedRunningByDisplay = runningByDisplay.filter({ k,v in
                NSWorkspace.shared.runningApplications.contains(where: {$0.processIdentifier == v.processIdentifier})
            })
            let prevHelperCount = runningByDisplay.count
            runningByDisplay = updatedRunningByDisplay
            if updatedRunningByDisplay.count != prevHelperCount {
                print("ScreenHelperProcessManager: a helper was launched or terminated")
            }
        }
    }
    
    private func helperApplicationURL() -> URL? {
        let bundle = Bundle.main.bundleURL
        let helperApp = bundle.appendingPathComponent("Contents/Helpers/BrightIntoshScreenHelper.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: helperApp.path) {
            return helperApp
        }
        return nil
    }
    
    /// Sync running helper apps to exactly the given XDR screens (launch new, terminate removed).
    func sync(xdrScreens: [NSScreen]) {
        print("ScreenHelperProcessManager: running sync \(String(describing: pendingLaunchDisplayIds)) \(String(describing: runningByDisplay))")
        self.xdrScreens = xdrScreens
        
        guard let helperAppURL = helperApplicationURL() else {
            print("ScreenHelperProcessManager: embedded BrightIntoshScreenHelper.app not found in bundle")
            return
        }
        
        for screen in xdrScreens {
            guard let id = screen.displayId else {
                print("ScreenHelperProcessManager: screen is missing display ID")
                continue
            }
            if runningByDisplay[id] != nil || pendingLaunchDisplayIds.contains(id) {
                print("ScreenHelperProcessManager: skipping display \(id) as it is already running/being launched")
                continue
            }
            
            pendingLaunchDisplayIds.insert(id)
                        
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.addsToRecentItems = false
            
            NSWorkspace.shared.openApplication(at: helperAppURL, configuration: configuration) { [weak self] runningApp, error in
                Task { @MainActor in
                    guard let self else {
                        return
                    }
                    self.pendingLaunchDisplayIds.remove(id)
                    
                    if let error {
                        print("ScreenHelperProcessManager: openApplication failed for display \(id): \(error)")
                        self.abortLaunchDisplayIds.remove(id)
                        return
                    }
                    
                    guard let runningApp else {
                        print("ScreenHelperProcessManager: openApplication returned nil app for display \(id)")
                        self.abortLaunchDisplayIds.remove(id)
                        return
                    }
                    
                    if self.abortLaunchDisplayIds.remove(id) != nil {
                        runningApp.terminate()
                        return
                    }
                    
                    self.runningByDisplay[id] = runningApp
                    print("ScreenHelperProcessManager: launched helper for display \(id) (pid \(runningApp.processIdentifier))")
                    
                    BrightIntoshSettings.shared.helpersInfo = self.runningByDisplay.map({"\($1.processIdentifier):\($0)"}).joined(separator: ",")
                    
                    print("Helper info: \(BrightIntoshSettings.shared.helpersInfo)")
                }
            }
        }
    }
    
    func terminateAll() {
        BrightIntoshSettings.shared.helpersInfo = ""
        runningByDisplay.removeAll()
        abortLaunchDisplayIds.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }
}
