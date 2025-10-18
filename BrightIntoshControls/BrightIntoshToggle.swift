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
    static let kind: String = "de.brightintosh.app.BrightIntoshControls.bup"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: Self.kind,
            provider: Provider()
        ) { value in
            ControlWidgetToggle(
                "Activate BrightIntosh",
                isOn: value,
                action: ToggleBrightIntoshIntent()
            ) { isRunning in
                Label(isRunning ? "On" : "Off", systemImage: "sun.max.circle")
            }
        }
        .displayName("BrightIntosh Toggle")
        .description("Activate or deactivate increased brightness.")
    }
}

extension BrightIntoshControlToggle {
    struct Value {
        var isRunning: Bool
        var name: String
    }

    struct Provider: ControlValueProvider {
        
        var previewValue: Bool {
            false
        }

        func currentValue() async throws -> Bool {
            let isRunning = UserDefaults(suiteName: "group.de.brightintosh.app")!.bool(forKey: "active")
            return isRunning
        }
    }
}

struct ToggleBrightIntoshIntent: SetValueIntent {
    static let title: LocalizedStringResource = "BrightIntosh toggle"

    @Parameter(title: "BrightIntosh is active")
    var value: Bool

    func perform() async throws -> some IntentResult {
        // Trigger main app via distributed notification; handled in AppDelegate
        let name = Notification.Name("de.brightintosh.intent.setActive")
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
        return .result()
    }
}
