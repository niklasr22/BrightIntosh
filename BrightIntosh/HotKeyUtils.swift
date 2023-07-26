//
//  HotKeyUtils.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 26.07.23.
//

import Cocoa
import Carbon

class HotKeyUtils {
    
    private static var hotkeyCounter: UInt32 = 0
    private static var hotkeyCallbacks: [UInt32: () -> Void] = [:]
    private static var hotkeyEventHandlers: [UInt32: EventHotKeyRef] = [:]
    
    static func registerHotKey(modifierFlags: UInt32, keyCode: UInt32, callback: @escaping () -> Void) {
        var hotKeyRef: EventHotKeyRef?
        
        var hotKeyId = EventHotKeyID()
        hotKeyId.id = hotkeyCounter
        
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyReleased)
        
        InstallEventHandler(GetApplicationEventTarget(), {
            nextHandler, event, userData -> OSStatus in
            HotKeyUtils.handleHotKeyPress(hotkeyId: EventHotKeyID().id)
            return noErr
        }, 1, &eventType, nil, nil)
        
        let status = RegisterEventHotKey(keyCode, modifierFlags, hotKeyId, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            print("Could not register hot key.")
            return
        }
        
        hotkeyEventHandlers[hotkeyCounter] = hotKeyRef
        hotkeyCallbacks[hotkeyCounter] = callback
        hotkeyCounter += 1
    }
    
    static func unregisterAllHotKeys() {
        for ref in hotkeyEventHandlers.values {
            UnregisterEventHotKey(ref)
        }
        hotkeyEventHandlers.removeAll()
        hotkeyCallbacks.removeAll()
        hotkeyCounter = 0
    }
    
    @objc static func handleHotKeyPress(hotkeyId: UInt32) {
        if let callback = hotkeyCallbacks[hotkeyId] {
            DispatchQueue.main.async {
                callback()
            }
        }
    }
}
