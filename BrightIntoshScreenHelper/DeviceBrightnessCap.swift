//
//  DeviceBrightnessCap.swift
//  BrightIntoshScreenHelper
//
//  Minimal copy of device max brightness logic (no BrightIntoshSettings / StoreKit).
//

import Foundation
import IOKit

private let sdr600nitsDevices: Set<String> = [
    "Mac15,3", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10", "Mac15,11",
    "Mac16,1", "Mac16,6", "Mac16,8", "Mac16,7", "Mac16,5",
    "Mac17,2", "Mac17,6", "Mac17,8", "Mac17,7", "Mac17,9"
]

private func modelIdentifier() -> String? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    defer { IOObjectRelease(service) }
    guard let modelData = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0)
        .takeRetainedValue() as? Data else {
        return nil
    }
    return String(data: modelData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
}

func screenHelperDeviceMaxBrightness() -> Float {
    if let model = modelIdentifier(), sdr600nitsDevices.contains(model) {
        return 1.535
    }
    return 1.59
}
