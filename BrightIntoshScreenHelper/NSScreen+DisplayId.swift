//
//  NSScreen+DisplayId.swift
//  BrightIntoshScreenHelper
//

import Cocoa

extension NSScreen {
    var displayId: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
}
