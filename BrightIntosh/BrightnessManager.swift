//
//  BrightnessManager.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 01.10.23.
//

import Foundation
import Cocoa

extension NSScreen {
    var displayId: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
}

class BrightnessManager {
    
    var brightnessTechnique: BrightnessTechnique?
    var screens: [NSScreen] = []
    var xdrScreens: [NSScreen] = []
    
    init(isExtraBrightnessAllowed: @escaping (Bool) async -> Bool) {
        setBrightnessTechnique()
        
        if Settings.shared.brightintoshActive {
            enableExtraBrightness()
        }
        
        // Observe displays
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParameters(notification:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        // Observe workspace for wake notification
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensWake(notification:)),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        
        // Add settings listeners
        Settings.shared.addListener(setting: "brightintoshActive") {
            print("Toggled increased brightness. Active: \(Settings.shared.brightintoshActive)")
            
            if Settings.shared.brightintoshActive {
                
                Task {
                    if await isExtraBrightnessAllowed(true) {
                        DispatchQueue.main.async {
                            self.enableExtraBrightness()
                        }
                    } else {
                        DispatchQueue.main.async {
                            Settings.shared.brightintoshActive = false
                        }
                    }
                }
            } else {
                self.brightnessTechnique?.disable()
            }
        }
        
        Settings.shared.addListener(setting: "brightness") {
            print("Set brightness to \(Settings.shared.brightness)")
            self.brightnessTechnique?.adjustBrightness()
        }
        
        Settings.shared.addListener(setting: "brightIntoshOnlyOnBuiltIn") {
            self.handlePotentialScreenUpdate()
        }
        
        screens = getXDRDisplays()
    }
    
    func setBrightnessTechnique() {
        brightnessTechnique?.disable()
        brightnessTechnique = GammaTechnique()
        print("Activated Gamma Technique")
    }
    
    @objc func handleScreenParameters(notification: Notification) {
        handlePotentialScreenUpdate()
    }
    
    @objc func screensWake(notification: Notification) {
        print("Wake up \(notification.name)")
        if let brightnessTechnique = brightnessTechnique, brightnessTechnique.isEnabled {
            brightnessTechnique.adjustBrightness()
        }
    }
    
    func handlePotentialScreenUpdate() {
        let newScreens = NSScreen.screens
        let newXdrDisplays = getXDRDisplays()
        var changedScreens = newScreens.count != screens.count || newXdrDisplays.count != xdrScreens.count
        if !changedScreens {
            for screen in screens {
                let sameScreen = newScreens.filter({$0.displayId == screen.displayId }).first
                if sameScreen?.frame.origin != screen.frame.origin {
                    changedScreens = true;
                    break
                }
            }
        }
        
        if changedScreens {
            print("Screen setup changed")
            screens = newScreens
            xdrScreens = newXdrDisplays
        }
        
        if !newScreens.isEmpty {
            if let brightnessTechnique = brightnessTechnique, Settings.shared.brightintoshActive {
                if !brightnessTechnique.isEnabled {
                    print("Enable extra brightness after screen setup change")
                    self.enableExtraBrightness()
                } else if changedScreens {
                    brightnessTechnique.screenUpdate(screens: xdrScreens)
                } else {
                    brightnessTechnique.adjustBrightness()
                }
            }
        } else {
            print("Disabling")
            self.brightnessTechnique?.disable()
        }
    }
    
    func enableExtraBrightness() {
        // Put brightness value into device specific bounds, as earlier versions allowed storing higher brightness values.
        let safeBrightness = max(1.0, min(getDeviceMaxBrightness(), Settings.shared.brightness))
        
        if safeBrightness != Settings.shared.brightness {
            print("Fixing brightness")
            Settings.shared.brightness = safeBrightness
        }
        self.brightnessTechnique?.enable()
    }
}
