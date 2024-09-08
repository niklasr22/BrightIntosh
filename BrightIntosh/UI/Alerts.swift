//
//  Alerts.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 02.10.23.
//

import Foundation
import Cocoa

func createBatteryAutomationContradictionAlert() -> NSAlert {
    let alert = NSAlert()
    alert.messageText = "Your battery level is below \(Settings.shared.batteryAutomationThreshold)%. Do you want to activate increased brightness anyway?\n\nThis will disable the battery automation."
    alert.addButton(withTitle: "Continue")
    alert.addButton(withTitle: "Cancel")
    return alert
}
