//
//  Constants.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 22.09.23.
//

import Carbon
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleBrightIntosh = Self("toggleIncreasedBrightness", default: .init(carbonKeyCode: kVK_ANSI_B, carbonModifiers: (0 | optionKey | cmdKey)))
    static let increaseBrightness = Self("increaseBrightness", default: .init(carbonKeyCode: kVK_ANSI_N, carbonModifiers: (0 | optionKey | cmdKey)))
    static let decreaseBrightness = Self("decreaseBrightness", default: .init(carbonKeyCode: kVK_ANSI_M, carbonModifiers: (0 | optionKey | cmdKey)))
}

let launcherBundleId = "de.brightintosh.launcher" as CFString
let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)!
