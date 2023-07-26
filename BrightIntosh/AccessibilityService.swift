//
//  AccessibilityService.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 19.07.23.
//

import Cocoa

/* TODO: Use this once Carbon is fully deprecated without a better successor.
 final class AccessibilityService {
    
    private static var trusted = false
    private static var running = false
    
    private static func pollIsTrustedProcess(getsTrusted: @escaping () -> ()) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            AccessibilityService.trusted = AXIsProcessTrusted()
            if !AccessibilityService.trusted {
                AccessibilityService.pollIsTrustedProcess(getsTrusted: getsTrusted)
            } else {
                getsTrusted()
            }
        }
    }
    
    static func startPollingTrustedProcessState(getsTrusted: @escaping () -> ()) {
        if AccessibilityService.running {
            return
        }
        AccessibilityService.running = true
        pollIsTrustedProcess(getsTrusted: getsTrusted)
    }
    
}
*/
