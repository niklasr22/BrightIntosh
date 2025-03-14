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
    
    private var timerAutomationTimer: Timer?
    
    init() {
        if Settings.shared.batteryAutomation {
            startBatteryAutomation()
        }
        
        Settings.shared.addListener(setting: "batteryAutomation") {
            print("Toggled battery automation. Active: \(Settings.shared.batteryAutomation)")
            
            if Settings.shared.batteryAutomation {
                self.startBatteryAutomation()
            } else {
                self.stopBatteryAutomation()
            }
        }
        
        if Settings.shared.timerAutomation && Settings.shared.brightintoshActive {
            startTimerAutomation()
        }
        
        Settings.shared.addListener(setting: "timerAutomation") {
            print("Toggled Timer automation. Active: \(Settings.shared.timerAutomation)")
            
            if Settings.shared.timerAutomation && Settings.shared.brightintoshActive {
                self.startTimerAutomation()
            } else {
                self.stopTimerAutomation()
            }
        }
        
        Settings.shared.addListener(setting: "timerAutomationTimeout") {
            print("Changed Timer Automation Timeout: \(Settings.shared.timerAutomationTimeout)")
            
            if Settings.shared.timerAutomation && Settings.shared.brightintoshActive{
                self.restartTimerAutomation()
            }
        }
        
        Settings.shared.addListener(setting: "brightintoshActive") {
            if Settings.shared.brightintoshActive && Settings.shared.timerAutomation {
                self.startTimerAutomation()
                print("Toggled increased Brightness with timeout. Timer started.")
            } else if !Settings.shared.brightintoshActive {
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
        if !Settings.shared.brightintoshActive {
            return
        }
        if let batteryCapacity = getBatteryCapacity() {
            let threshold = Settings.shared.batteryAutomationThreshold
            if batteryCapacity <= threshold {
                print("Battery level dropped below \(threshold)%. Deactivating increased brightness.")
                Settings.shared.brightintoshActive = false
                stopTimerAutomation()
            }
        }
    }
    
    func startTimerAutomation() {
        if timerAutomationTimer != nil || !Settings.shared.brightintoshActive {
            return
        }
        let timeout = Settings.shared.timerAutomationTimeout
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
        Settings.shared.brightintoshActive = false
        stopTimerAutomation()
    }
    
    func getRemainingTime() -> Double {
        return timerAutomationTimer != nil ? Date.now.distance(to: timerAutomationTimer!.fireDate) / 60 : 0.0
    }
    
}
