//
//  AppDelegate.swift
//  AutoLauncher
//
//  Created by Niklas Rousset on 11.08.23.
//

import Cocoa

class LauncherAppDelegate: NSObject, NSApplicationDelegate {

    static let mainApplicationBundleId = "de.brightintosh.app"
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = runningApps.contains { app -> Bool in
            app.bundleIdentifier == LauncherAppDelegate.mainApplicationBundleId
        }
        
        if !isRunning {
            /*if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: LauncherAppDelegate.mainApplicationBundleId) {
                NSWorkspace.shared.launchApplication(url.path)
            }*/
            var path = Bundle.main.bundlePath as NSString
            for _ in 1...4 {
                path = path.deletingLastPathComponent as NSString
            }
            NSWorkspace.shared.launchApplication(path as String)
        }
    }

}

