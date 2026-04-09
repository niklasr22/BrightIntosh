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
    
    private let screenHelperManager = ScreenHelperProcessManager()
    var screens: [NSScreen] = []
    var xdrScreens: [NSScreen] = []
    var enabled: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private var screenUpdateDebounceTask: Task<Void, Never>?
    
    init() {
        if BrightIntoshSettings.shared.brightintoshActive {
            activateSafely()
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParameters(notification:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        Authorizer.shared.$status.sink { newStatus in
            if newStatus == .unauthorized && BrightIntoshSettings.shared.brightintoshActive {
                BrightIntoshSettings.shared.brightintoshActive = false
            }
        }.store(in: &cancellables)
        
        BrightIntoshSettings.shared.addListener(setting: "brightintoshActive") {
            if BrightIntoshSettings.shared.brightintoshActive {
                self.activateSafely()
            } else if self.enabled {
                self.screenHelperManager.terminateAll()
            }
        }
        
        BrightIntoshSettings.shared.addListener(setting: "brightness") {
            print("Set brightness to \(BrightIntoshSettings.shared.brightness)")
        }
        
        BrightIntoshSettings.shared.addListener(setting: "brightIntoshOnlyOnBuiltIn") {
            self.handlePotentialScreenUpdate()
        }
        
        screens = NSScreen.screens
        xdrScreens = getXDRDisplays()
    }
    
    func activateSafely() {
        if Authorizer.shared.isAllowed() {
            self.enabled = true
            self.enableExtraBrightness()
        } else {
            BrightIntoshSettings.shared.brightintoshActive = false
        }
    }
    
    @MainActor @objc func handleScreenParameters(notification: Notification) {
        print("Screen parameters changed")
        scheduleDebouncedScreenUpdate()
    }
    
    @MainActor func handlePotentialScreenUpdate() {
        let newScreens = NSScreen.screens
        let newXdrDisplays = getXDRDisplays()
        var changedScreens = newScreens.count != screens.count || newXdrDisplays.count != xdrScreens.count
        let screenWasRemoved = newScreens.count < screens.count || newXdrDisplays.count < xdrScreens.count
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
            if BrightIntoshSettings.shared.brightintoshActive {
                screenHelperManager.sync(xdrScreens: newXdrDisplays)
            }
        } else {
            print("Disabling")
            screenHelperManager.terminateAll()
        }
    }
    
    @MainActor
    private func enableExtraBrightness() {
        let safeBrightness = max(1.0, min(getDeviceMaxBrightness(), BrightIntoshSettings.shared.brightness))
        
        if safeBrightness != BrightIntoshSettings.shared.brightness {
            print("Fixing brightness")
            BrightIntoshSettings.shared.brightness = safeBrightness
        }
        screenHelperManager.sync(xdrScreens: getXDRDisplays())
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
}
