//
//  BatteryAutomation.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 02.10.23.
//

import Foundation
import IOKit.ps
import Cocoa

enum BatteryReadingError: Error {
    case error
}

func getBatteryCapacity() -> Int? {
    do {
        guard let powerSourcesInformation = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            throw BatteryReadingError.error
        }
        
        guard let powerSources: NSArray = IOPSCopyPowerSourcesList(powerSourcesInformation)?.takeRetainedValue() else {
            throw BatteryReadingError.error
        }
        
        for powerSource in powerSources {
            guard let info: NSDictionary = IOPSGetPowerSourceDescription(powerSourcesInformation, powerSource as CFTypeRef)?.takeUnretainedValue() else {
                throw BatteryReadingError.error
            }
            
            if let name = info[kIOPSNameKey] as? String,
               let capacity = info[kIOPSCurrentCapacityKey] as? Int {
                if name == "InternalBattery-0" {
                    return capacity
                }
            }
        }
    } catch {
        return nil
    }
    return nil
}

/// Runs checks if increased brightness activation would be toggling an immediate deactivation through the battery automation.
/// If this is the case, an alert is shown to let the user decide wether to continue by deactivating the automation or not,
/// - Returns: Bool wether increased brightness can be enabled or not
@MainActor func checkBatteryAutomationContradiction() -> Bool {
    if Settings.shared.batteryAutomation {
        if let batteryCapacity = getBatteryCapacity(), batteryCapacity <= Settings.shared.batteryAutomationThreshold {
            let alert = createBatteryAutomationContradictionAlert()
            let result = alert.runModal()
            if result == NSApplication.ModalResponse.alertFirstButtonReturn {
                Settings.shared.batteryAutomation = false
            } else if result == NSApplication.ModalResponse.alertSecondButtonReturn {
                return false
            }
        }
    }
    return true
}
