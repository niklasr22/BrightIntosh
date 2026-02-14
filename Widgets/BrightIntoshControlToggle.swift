//
//  BtnControl.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 17.10.25.
//

import AppIntents
import SwiftUI
import WidgetKit
import Foundation

struct BrightIntoshControlToggle: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: brightintoshActiveControlKind,
            provider: Provider()
        ) { value in
            ControlWidgetToggle(
                "Activate BrightIntosh",
                isOn: value,
                action: ToggleBrightIntoshIntent()
            ) { isRunning in
                Image(systemName: "sun.max.circle")
                Text(isRunning ? "On" : "Off")
            }
        }
        .displayName("BrightIntosh Toggle")
        .description("Activate or deactivate increased brightness.")
    }
}

extension BrightIntoshControlToggle {
    struct Provider: ControlValueProvider {
        
        var previewValue: Bool {
            false
        }

        func currentValue() async throws -> Bool {
            let isRunning = UserDefaults(suiteName: defaultsSuiteName)!.bool(forKey: "active")
            return isRunning
        }
    }
}

struct ToggleBrightIntoshIntent: SetValueIntent {
    static let title: LocalizedStringResource = "BrightIntosh Toggle"

    @Parameter(title: "BrightIntosh is active")
    var value: Bool

    func perform() async throws -> some IntentResult {
        // Trigger main app via distributed notification; handled in AppDelegate
        //DistributedNotificationCenter.default().postNotificationName(controlActiveToggleNotificationName, object: nil, userInfo: nil, deliverImmediately: true)
        UserDefaults(suiteName: defaultsSuiteName)!.setValue(value, forKey: "active")
        return .result()
    }
}
