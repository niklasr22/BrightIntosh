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
    private var screenUpdateDebounceTask: Task<Void, Never>?
    
    init() {
        setBrightnessTechnique()
        screens = NSScreen.screens
        xdrScreens = getXDRDisplays()
        
        if BrightIntoshSettings.shared.brightintoshActive {
            if shouldDisableForClosedLid(currentScreens: screens) {
                BrightIntoshSettings.shared.brightintoshActive = false
            } else {
                activateSafely()
            }
        }
        
        // Observe displays
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParameters(notification:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )


        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleScreensSleep(notification:)),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeFromSleep(notification:)),
            name: NSWorkspace.didWakeNotification,
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

        BrightIntoshSettings.shared.addListener(setting: "disableWhenLidClosed") {
            self.handlePotentialScreenUpdate()
        }
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
        scheduleDebouncedScreenUpdate()
    }
    
    @MainActor @objc func handleWakeFromSleep(notification: Notification) {
        guard BrightIntoshSettings.shared.brightintoshActive && enabled else {
            return
        }
        print("Restoring color sync settings after wake from sleep")
        CGDisplayRestoreColorSyncSettings()
        scheduleDebouncedScreenUpdate()
    }
    
    @MainActor @objc func handleScreensSleep(notification: Notification) {
        print("Restoring color sync settings as screens sleep")
        CGDisplayRestoreColorSyncSettings()
    }
    
    @MainActor func handlePotentialScreenUpdate() {
        let newScreens = NSScreen.screens
        let newXdrDisplays = getXDRDisplays()
        var changedScreens = newScreens.count != screens.count || newXdrDisplays.count != xdrScreens.count
        let screenWasRemoved = newScreens.count < screens.count || newXdrDisplays.count < xdrScreens.count
        let screenWasAdded = newScreens.count > screens.count || newXdrDisplays.count > xdrScreens.count
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

        if BrightIntoshSettings.shared.brightintoshActive && shouldDisableForClosedLid(currentScreens: newScreens) {
            BrightIntoshSettings.shared.brightintoshActive = false
            return
        }
        
        guard enabled else {
            return
        }
        
        if !newScreens.isEmpty {
            if let brightnessTechnique = brightnessTechnique, BrightIntoshSettings.shared.brightintoshActive {
                if changedScreens && screenWasRemoved {
                    print("Screen removed, updating active displays")
                    brightnessTechnique.screenUpdate(screens: newXdrDisplays)
                } else if changedScreens && screenWasAdded && brightnessTechnique.isEnabled {
                    print("Screen attached, enabling increased brightness immediately")
                    brightnessTechnique.screenUpdate(screens: newXdrDisplays)
                } else if changedScreens && brightnessTechnique.isEnabled {
                    print("Changed screen setup")
                    brightnessTechnique.screenUpdate(screens: newXdrDisplays)
                } else if brightnessTechnique.isEnabled {
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
            BrightIntoshSettings.shared.brightness = safeBrightness
        }
        self.brightnessTechnique?.enable()
    }
    @MainActor
    private func scheduleDebouncedScreenUpdate() {
        screenUpdateDebounceTask?.cancel()
        screenUpdateDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            
            guard !Task.isCancelled else {
                return
            }
            
            self.handlePotentialScreenUpdate()
        }
    }

    @MainActor
    private func shouldDisableForClosedLid(currentScreens: [NSScreen]) -> Bool {
        guard BrightIntoshSettings.shared.disableWhenLidClosed else {
            return false
        }
        if let clamshellClosed = isClamshellClosed() {
            return clamshellClosed
        }
        // Fallback if clamshell state is unavailable.
        return !currentScreens.isEmpty && !currentScreens.contains(where: { isBuiltInScreen(screen: $0) })
    }
    
}
