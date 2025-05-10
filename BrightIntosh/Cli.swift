//
//  Cli.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 10.05.25.
//
import Foundation

@MainActor func notifyUpdate() {
    let center = DistributedNotificationCenter.default()
    center.postNotificationName(UserDefaults.didChangeNotification, object: nil, userInfo: nil, deliverImmediately: true)
}

@MainActor func toggleCli() {
    Settings.shared.brightintoshActive.toggle()
    notifyUpdate()
}

@MainActor func setActiveState(active: Bool) {
    Settings.shared.brightintoshActive = active
    notifyUpdate()
}

@MainActor func statusCli() {
    let status = Settings.shared.brightintoshActive
    print("Status: \(status ? "Enabled" : "Disabled")")
    print("Brightness: \(Settings.shared.brightness)")
}

func helpCli() {
    print("Available commands: toggle, enable, disable, status, help")
}

@MainActor func cliBase() -> Bool {
    if CommandLine.argc > 1 {
        let command = CommandLine.arguments[1]
        switch command {
        case "toggle":
            toggleCli()
            return true
        case "enable":
            setActiveState(active: true)
            return true
        case "disable":
            setActiveState(active: false)
            return true
        case "status":
            statusCli()
            return true
        case "help":
            helpCli()
            return true
        default:
            helpCli()
            break
        }
    }
    return false
}
