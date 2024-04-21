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
    var extraBrightnessAllowed = false;
    
    init(brightnessAllowed: Bool) {
        self.extraBrightnessAllowed = brightnessAllowed
        if !self.extraBrightnessAllowed {
            Settings.shared.brightintoshActive = false;
        }
        
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
        
        // Add settings listeners
        Settings.shared.addListener(setting: "brightintoshActive") {
            print("Toggled increased brightness. Active: \(Settings.shared.brightintoshActive)")
            
            if Settings.shared.brightintoshActive {
                self.enableExtraBrightness()
            } else {
                self.brightnessTechnique?.disable()
            }
        }
        
        Settings.shared.addListener(setting: "brightness") {
            print("Set brightness to \(Settings.shared.brightness)")
            if let brightnessTechnique = self.brightnessTechnique, brightnessTechnique.isEnabled {
                self.brightnessTechnique?.adjustBrightness()
            }
        }
    }
    
    func setBrightnessTechnique() {
        brightnessTechnique?.disable()
        brightnessTechnique = GammaTechnique()
        print("Activated Gamma Technique")
    }
    
    @objc func handleScreenParameters(notification: Notification) {
        let screens = getXDRDisplays()
        print("Available XDR displays: \(screens.count)")
        if !screens.isEmpty {
            if let brightnessTechnique = brightnessTechnique, Settings.shared.brightintoshActive {
                if !brightnessTechnique.isEnabled {
                    enableExtraBrightness()
                } else {
                    brightnessTechnique.screenUpdate(screens: screens)
                }
            }
        } else {
            brightnessTechnique?.disable()
        }
    }
    
    func enableExtraBrightness() {
        if extraBrightnessAllowed {
            // Put brightness value into device specific bounds, as earlier versions allowed storing higher brightness values.
            Settings.shared.brightness = max(1.0, min(getDeviceMaxBrightness(), Settings.shared.brightness))
            self.brightnessTechnique?.enable()
        }
    }
}


func getBuiltInScreen() -> NSScreen? {
    for screen in NSScreen.screens {
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        let displayId: CGDirectDisplayID = screenNumber as! CGDirectDisplayID
        if (CGDisplayIsBuiltin(displayId) != 0) {
            return screen
        }
    }
    return nil
}

func getXDRDisplays() -> [NSScreen] {
    var xdrScreens: [NSScreen] = []
    for screen in NSScreen.screens {
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        // let displayId: CGDirectDisplayID = screenNumber as! CGDirectDisplayID
        //if (CGDisplayIsBuiltin(displayId) != 0 || screen.localizedName == "Pro Display XDR") {
            xdrScreens.append(screen)
        //}
    }
    return xdrScreens
}
