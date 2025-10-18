//
//  BatteryAutomation.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 02.10.23.
//

import Foundation
import IOKit.ps
import Cocoa

private let INTERNAL_BATTERY_NAME = "InternalBattery-0"

enum BatteryReadingError: Error {
    case error
}

private func getPowerSources() throws -> [NSDictionary] {
    guard let powerSourcesInformation = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
        throw BatteryReadingError.error
    }
        
    guard let powerSources: NSArray = IOPSCopyPowerSourcesList(powerSourcesInformation)?.takeRetainedValue() else {
        throw BatteryReadingError.error
    }
    
    return try powerSources.map {
        guard let info: NSDictionary = IOPSGetPowerSourceDescription(powerSourcesInformation, $0 as CFTypeRef)?.takeUnretainedValue() else {
                throw BatteryReadingError.error
            }
        return info
    }
}

func getBatteryCapacity() -> Int? {
    do {
        let powerSources = try getPowerSources()
        for powerSource in powerSources {
            
            if powerSource[kIOPSNameKey] as? String == INTERNAL_BATTERY_NAME {
                return powerSource[kIOPSCurrentCapacityKey] as? Int
            }
        }
    } catch {
        return nil
    }
    return nil
}

func isPowerAdapterConnected() -> Bool {
    do {
        let powerSources = try getPowerSources()
        for powerSource in powerSources {
            if powerSource[kIOPSNameKey] as? String == INTERNAL_BATTERY_NAME {
                return powerSource[kIOPSPowerSourceStateKey] as? String == "AC Power"
            }
        }
    } catch {
        return false
    }
    return false
}

/// Runs checks if increased brightness activation would be toggling an immediate deactivation through the battery automation.
/// If this is the case, an alert is shown to let the user decide wether to continue by deactivating the automation or not,
/// - Returns: Bool wether increased brightness can be enabled or not
@MainActor func checkBatteryAutomationContradiction() -> Bool {
    if BrightIntoshSettings.shared.batteryAutomation {
        if let batteryCapacity = getBatteryCapacity(), batteryCapacity <= BrightIntoshSettings.shared.batteryAutomationThreshold {
            let alert = createBatteryAutomationContradictionAlert()
            let result = alert.runModal()
            if result == NSApplication.ModalResponse.alertFirstButtonReturn {
                BrightIntoshSettings.shared.batteryAutomation = false
            } else if result == NSApplication.ModalResponse.alertSecondButtonReturn {
                return false
            }
        }
    }
    return true
}
