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

let supportedDevices = ["MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4", "Mac14,6", "Mac14,10", "Mac14,5", "Mac14,9", "Mac15,7", "Mac15,9", "Mac15,11", "Mac15,6", "Mac15,8", "Mac15,10", "Mac15,3"]
