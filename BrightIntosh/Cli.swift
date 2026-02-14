//
//  Cli.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 10.05.25.
//
import Foundation

@MainActor func toggleCli() {
    BrightIntoshSettings.shared.brightintoshActive.toggle()
}

@MainActor func setActiveStateCli(active: Bool) {
    BrightIntoshSettings.shared.brightintoshActive = active
}

@MainActor func setBrightnessOffsetCli() {
    if CommandLine.argc <= 2 {
        print("Usage: brightintosh set <0-100>")
        return
    }
    guard let brightnessValue = Int(CommandLine.arguments[3]), brightnessValue <= 100, brightnessValue >= 0 else {
        print("Usage: brightintosh set <0-100>")
        return
    }
    BrightIntoshSettings.shared.brightness = 1.0 + (getDeviceMaxBrightness() - 1.0) * Float(brightnessValue) / 100.0
}

@MainActor func statusCli() {
    let status = BrightIntoshSettings.shared.brightintoshActive
    let brightness = BrightIntoshSettings.shared.brightness
    let brightnessPercentage = Int(round((brightness - 1.0) / (getDeviceMaxBrightness() - 1.0) * 100.0))
    print("Status: \(status ? "Enabled" : "Disabled")")
    print("Brightness: \(brightnessPercentage)")
}

enum CliCommand: String, CaseIterable {
    case enable = "enable"
    case disable = "disable"
    case set = "set"
    case status = "status"
    case toggle = "toggle"
    case help = "help"
    case cli = "cli"
}

func getHelpText() -> String {
    return
"""
BrightIntosh CLI
Usage: brightintosh <command> [options]

Note: This CLI is additional and does require the main app to be running.

Commands:
  enable       Enable BrightIntosh
  disable      Disable BrightIntosh
  set <value>  Set brightness offset (0-100)
  status       Show current status and brightness
  toggle       Toggle BrightIntosh on/off
  help         Show this help message
"""
}

func helpCli() {
    print(getHelpText())
}

@MainActor func cliBase() -> Bool {
    if CommandLine.argc > 1 {
        guard let cliMode = CliCommand(rawValue: CommandLine.arguments[1]), cliMode == .cli else {
            return false
        }
        
        guard CommandLine.argc > 2 else {
            helpCli()
            return true;
        }
        
        guard let command = CliCommand(rawValue: CommandLine.arguments[2]) else {
            helpCli()
            return true
        }
        
        switch command {
        case .toggle:
            toggleCli()
        case .enable:
            setActiveStateCli(active: true)
        case .disable:
            setActiveStateCli(active: false)
        case .set:
            setBrightnessOffsetCli()
        case .status:
            statusCli()
        case .help:
            helpCli()
        case .cli:
            helpCli()
        }
    }
    return true
}
