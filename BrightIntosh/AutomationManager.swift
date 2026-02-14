//
//  AutomationManager.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 02.10.23.
//

import Foundation

@MainActor
class AutomationManager {
    private let batteryCheckInterval = 10.0
    private var batteryCheckTimer: Timer?
    
    private let powerAdapterCheckInterval = 2.0
    private var powerAdapterCheckTimer: Timer?
    private var lastPowerAdapterPluggedInState: Bool?
    private var wasBrightnessPreUnplugActive = false;
    
    private var timerAutomationTimer: Timer?
    
    init() {
        if BrightIntoshSettings.shared.batteryAutomation {
            startBatteryAutomation()
        }
        
        if BrightIntoshSettings.shared.powerAdapterAutomation {
            startPowerAdapterAutomation()
        }
        
        BrightIntoshSettings.shared.addListener(setting: "batteryAutomation") {
            print("Toggled battery automation. Active: \(BrightIntoshSettings.shared.batteryAutomation)")
            
            if BrightIntoshSettings.shared.batteryAutomation {
                self.startBatteryAutomation()
            } else {
                self.stopBatteryAutomation()
            }
        }
        
        BrightIntoshSettings.shared.addListener(setting: "powerAdapterAutomation") {
            print("Toggled power adapter automation. Active: \(BrightIntoshSettings.shared.powerAdapterAutomation)")
            
            if BrightIntoshSettings.shared.powerAdapterAutomation {
                self.startPowerAdapterAutomation()
            } else {
                self.stopPowerAdapterAutomation()
            }
        }
        
        if BrightIntoshSettings.shared.timerAutomation && BrightIntoshSettings.shared.brightintoshActive {
            startTimerAutomation()
        }
        
        BrightIntoshSettings.shared.addListener(setting: "timerAutomation") {
            print("Toggled Timer automation. Active: \(BrightIntoshSettings.shared.timerAutomation)")
            
            if BrightIntoshSettings.shared.timerAutomation && BrightIntoshSettings.shared.brightintoshActive {
                self.startTimerAutomation()
            } else {
                self.stopTimerAutomation()
            }
        }
        
        BrightIntoshSettings.shared.addListener(setting: "timerAutomationTimeout") {
            print("Changed Timer Automation Timeout: \(BrightIntoshSettings.shared.timerAutomationTimeout)")
            
            if BrightIntoshSettings.shared.timerAutomation && BrightIntoshSettings.shared.brightintoshActive{
                self.restartTimerAutomation()
            }
        }
        
        BrightIntoshSettings.shared.addListener(setting: "brightintoshActive") {
            if BrightIntoshSettings.shared.brightintoshActive && BrightIntoshSettings.shared.timerAutomation {
                self.startTimerAutomation()
                print("Toggled increased Brightness with timeout. Timer started.")
            } else if !BrightIntoshSettings.shared.brightintoshActive {
                self.stopTimerAutomation()
            }
        }
    }
    
    func startBatteryAutomation() {
        if batteryCheckTimer != nil {
            return
        }
        let batteryCheckDate = Date()
        batteryCheckTimer = Timer(fire: batteryCheckDate, interval: batteryCheckInterval, repeats: true, block: {t in
            Task { @MainActor in
                self.checkBatteryAutomation()
            }
        })
        RunLoop.main.add(batteryCheckTimer!, forMode: RunLoop.Mode.default)
        print("Started battery automation")
    }
    
    func stopBatteryAutomation() {
        if batteryCheckTimer != nil {
            batteryCheckTimer?.invalidate()
            batteryCheckTimer = nil
        }
    }
    
    func checkBatteryAutomation() {
        if !BrightIntoshSettings.shared.brightintoshActive {
            return
        }
        if let batteryCapacity = getBatteryCapacity() {
            let threshold = BrightIntoshSettings.shared.batteryAutomationThreshold
            if batteryCapacity <= threshold {
                print("Battery level dropped below \(threshold)%. Deactivating increased brightness.")
                BrightIntoshSettings.shared.brightintoshActive = false
                stopTimerAutomation()
            }
        }
    }
    
    func startTimerAutomation() {
        if timerAutomationTimer != nil || !BrightIntoshSettings.shared.brightintoshActive {
            return
        }
        let timeout = BrightIntoshSettings.shared.timerAutomationTimeout
        timerAutomationTimer = Timer(timeInterval: Double(timeout * 60), repeats: false, block: { t in
            Task { @MainActor in
                self.timerAutomationCallback()
            }
        })
        RunLoop.main.add(self.timerAutomationTimer!, forMode: RunLoop.Mode.common)
    }
    
    func stopTimerAutomation() {
        if timerAutomationTimer != nil {
            timerAutomationTimer?.invalidate()
            timerAutomationTimer = nil
            print("Timer Automation Timer reset.")
        }
    }
    
    func restartTimerAutomation() {
        stopTimerAutomation()
        startTimerAutomation()
    }
    
    func timerAutomationCallback() {
        print("Timer fired. Deactivating increased brightness.")
        BrightIntoshSettings.shared.brightintoshActive = false
        stopTimerAutomation()
    }
    
    func getRemainingTime() -> Double {
        return timerAutomationTimer != nil ? Date.now.distance(to: timerAutomationTimer!.fireDate) / 60 : 0.0
    }
    
    func startPowerAdapterAutomation() {
        if powerAdapterCheckTimer != nil {
            return
        }
        lastPowerAdapterPluggedInState = isPowerAdapterConnected()
        wasBrightnessPreUnplugActive = false
        let powerAdapterCheckDate = Date()
        powerAdapterCheckTimer = Timer(fire: powerAdapterCheckDate, interval: powerAdapterCheckInterval, repeats: true, block: {t in
            Task { @MainActor in
                self.checkPowerAdapterAutomation()
            }
        })
        RunLoop.main.add(powerAdapterCheckTimer!, forMode: RunLoop.Mode.default)
        print("Started power adapter automation")
    }
    
    func stopPowerAdapterAutomation() {
        if powerAdapterCheckTimer != nil {
            powerAdapterCheckTimer?.invalidate()
            powerAdapterCheckTimer = nil
            lastPowerAdapterPluggedInState = nil
        }
    }
    
    func checkPowerAdapterAutomation() {
        let currentPowerStatePluggedIn = isPowerAdapterConnected()
        
        if lastPowerAdapterPluggedInState != currentPowerStatePluggedIn {
            lastPowerAdapterPluggedInState = currentPowerStatePluggedIn
            
            if currentPowerStatePluggedIn {
                if !BrightIntoshSettings.shared.brightintoshActive && wasBrightnessPreUnplugActive {
                    print("Power adapter connected. Activating increased brightness.")
                    BrightIntoshSettings.shared.brightintoshActive = true
                }
            } else {
                wasBrightnessPreUnplugActive = BrightIntoshSettings.shared.brightintoshActive
                if BrightIntoshSettings.shared.brightintoshActive {
                    print("Power adapter disconnected. Deactivating increased brightness.")
                    BrightIntoshSettings.shared.brightintoshActive = false
                    stopTimerAutomation()
                }
            }
        }
    }
}
