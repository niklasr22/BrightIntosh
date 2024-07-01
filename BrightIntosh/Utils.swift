//
//  Utils.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 01.01.24.
//

import Foundation
import IOKit

func getModelIdentifier() -> String? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    var modelIdentifier: String?
    if let modelData = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0).takeRetainedValue() as? Data {
        modelIdentifier = String(data: modelData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
    }

    IOObjectRelease(service)
    return modelIdentifier
}

func isDeviceSupported() -> Bool {
    if let device = getModelIdentifier(), supportedDevices.contains(device) {
        return true
    }
    return false
}

func getDeviceMaxBrightness() -> Float {
    if let device = getModelIdentifier(),
        sdr600nitsDevices.contains(device) {
        return 1.54
    }
    return 1.6
}

func runOnMainAfter(nanoseconds: Int, action: @escaping () -> Void) {
    Task {
        do {
            try await Task.sleep(nanoseconds: 500_000_000)
        } catch { }
        DispatchQueue.main.async {
            action()
        }
    }
}
