//
//  Alerts.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 02.10.23.
//

import Foundation
import Cocoa

@MainActor func createBatteryAutomationContradictionAlert() -> NSAlert {
    let alert = NSAlert()
    alert.messageText = "Your battery level is below \(BrightIntoshSettings.shared.batteryAutomationThreshold)%. Do you want to activate increased brightness anyway?\n\nThis will disable the battery automation."
    alert.addButton(withTitle: "Continue")
    alert.addButton(withTitle: "Cancel")
    return alert
}

@MainActor func createGammaConflictAlert() -> NSAlert {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = String(localized: "Increased brightness was disabled")
    alert.informativeText = String(localized: "Another app or system process repeatedly changed the display gamma values BrightIntosh applied. BrightIntosh stopped increased brightness to avoid flickering.")
    alert.addButton(withTitle: String(localized: "OK"))
    return alert
}
