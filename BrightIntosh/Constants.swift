//
//  Constants.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 22.09.23.
//

import Carbon
import KeyboardShortcuts
import SwiftUI

extension Color {
    static let brightintoshBlue = Color(red: 0.25, green: 0.67, blue: 0.79)
    static let brightintoshBluePressed = Color(red: 0.36, green: 0.74, blue: 0.84)
}

extension KeyboardShortcuts.Name {
    static let toggleBrightIntosh = Self("toggleIncreasedBrightness", default: .init(carbonKeyCode: kVK_ANSI_B, carbonModifiers: (0 | optionKey | cmdKey)))
    static let increaseBrightness = Self("increaseBrightness", default: .init(carbonKeyCode: kVK_ANSI_N, carbonModifiers: (0 | optionKey | cmdKey)))
    static let decreaseBrightness = Self("decreaseBrightness", default: .init(carbonKeyCode: kVK_ANSI_M, carbonModifiers: (0 | optionKey | cmdKey)))
}

let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)!

#if DEBUG
let supportedDevices = ["MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4", "Mac14,6", "Mac14,10", "Mac14,5", "Mac14,9", "Mac15,7", "Mac15,9", "Mac15,11", "Mac15,6", "Mac15,8", "Mac15,10", "Mac15,3", "MacBookAir10,1"
]
let externalXdrDisplays = ["Pro Display XDR", "C34H89x"]
#else
let supportedDevices = ["MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4", "Mac14,6", "Mac14,10", "Mac14,5", "Mac14,9", "Mac15,7", "Mac15,9", "Mac15,11", "Mac15,6", "Mac15,8", "Mac15,10", "Mac15,3",
]
let externalXdrDisplays = ["Pro Display XDR"]
#endif
let sdr600nitsDevices = ["Mac15,3", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10", "Mac15,11"]

struct Acknowledgment: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

private let keyboardShortcutsAcknowledgement = Acknowledgment(title: "KeyboardShortcuts", text: """
MIT License

Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
"""
)

let acknowledgments: [Acknowledgment] = [
    keyboardShortcutsAcknowledgement
]
