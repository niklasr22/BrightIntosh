//
//  BatteryAutomation.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 02.10.23.
//

import Foundation
import IOKit.ps

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
