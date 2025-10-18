//
//  BrightnessManager.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 01.10.23.
//

import Foundation
import Cocoa
import Combine

extension NSScreen {
    var displayId: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
}

@MainActor
class BrightnessManager {
    
    var brightnessTechnique: BrightnessTechnique?
    var screens: [NSScreen] = []
    var xdrScreens: [NSScreen] = []
    var enabled: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setBrightnessTechnique()
        
        if BrightIntoshSettings.shared.brightintoshActive {
            activateSafely()
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
        
        // Observe entitlement
        Authorizer.shared.$status.sink { newStatus in
            if newStatus == .unauthorized && BrightIntoshSettings.shared.brightintoshActive {
                BrightIntoshSettings.shared.brightintoshActive = false
            }
        }.store(in: &cancellables)
        
        // Add settings listeners
        BrightIntoshSettings.shared.addListener(setting: "brightintoshActive") {
            if BrightIntoshSettings.shared.brightintoshActive {
                self.activateSafely()
            } else if self.enabled {
                self.brightnessTechnique?.disable()
            }
        }
        
        BrightIntoshSettings.shared.addListener(setting: "brightness") {
            print("Set brightness to \(BrightIntoshSettings.shared.brightness)")
            self.brightnessTechnique?.adjustBrightness()
        }
        
        BrightIntoshSettings.shared.addListener(setting: "brightIntoshOnlyOnBuiltIn") {
            self.handlePotentialScreenUpdate()
        }
        
        screens = getXDRDisplays()
    }
    
    func activateSafely() {
        if Authorizer.shared.isAllowed() {
            self.enabled = true
            self.enableExtraBrightness()
        } else {
            BrightIntoshSettings.shared.brightintoshActive = false
        }
    }
    
    func setBrightnessTechnique() {
        brightnessTechnique?.disable()
        brightnessTechnique = GammaTechnique()
        print("Activated Gamma Technique")
    }
    
    @MainActor @objc func handleScreenParameters(notification: Notification) {
        handlePotentialScreenUpdate()
    }
    
    @objc func screensWake(notification: Notification) {
        print("Wake up \(notification.name)")
        if let brightnessTechnique = brightnessTechnique, brightnessTechnique.isEnabled {
            brightnessTechnique.adjustBrightness()
        }
    }
    
    @MainActor func handlePotentialScreenUpdate() {
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
        
        guard enabled else {
            return
        }
        
        if !newScreens.isEmpty {
            if let brightnessTechnique = brightnessTechnique, BrightIntoshSettings.shared.brightintoshActive {
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
    
    @MainActor
    private func enableExtraBrightness() {
        // Put brightness value into device specific bounds, as earlier versions allowed storing higher brightness values.
        let safeBrightness = max(1.0, min(getDeviceMaxBrightness(), BrightIntoshSettings.shared.brightness))
        
        if safeBrightness != BrightIntoshSettings.shared.brightness {
            print("Fixing brightness")
            BrightIntoshSettings.shared.brightness = safeBrightness
        }
        self.brightnessTechnique?.enable()
    }
}
