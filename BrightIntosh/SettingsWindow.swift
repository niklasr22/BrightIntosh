//
//  SettingsWindow.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 17.09.23.
//

import SwiftUI
import KeyboardShortcuts
#if !STORE
import Sparkle
#endif

final class BasicSettingsViewModel: ObservableObject {
    /*
     This View Model is used for settings that can be changed via shortcuts or another way other than the settings UI, so changes can be obeserved and showed in the UI.
     */
    private var brightIntoshActive = Settings.shared.brightintoshActive
    var brightIntoshActiveToggle: Bool {
        set { Settings.shared.brightintoshActive = newValue }
        get { return brightIntoshActive }
    }
    private var brightness = Settings.shared.brightness
    var brightnessSlider: Float {
        set { Settings.shared.brightness = newValue }
        get { return brightness }
    }
    private var batteryAutomation = Settings.shared.batteryAutomation
    var batteryAutomationToggle: Bool {
        set { Settings.shared.batteryAutomation = newValue }
        get { return batteryAutomation }
    }
    
    private var timerAutomation = Settings.shared.timerAutomation
    var timerAutomationToggle: Bool {
        set { Settings.shared.timerAutomation = newValue}
        get { return timerAutomation}
    }
    
    init() {
        Settings.shared.addListener(setting: "brightintoshActive") {
            if Settings.shared.brightintoshActive && !checkBatteryAutomationContradiction() {
                Settings.shared.brightintoshActive = false
            }
            if self.brightIntoshActive != Settings.shared.brightintoshActive {
                self.brightIntoshActive = Settings.shared.brightintoshActive
                self.objectWillChange.send()
            }
        }
        Settings.shared.addListener(setting: "brightness") {
            if self.brightness != Settings.shared.brightness {
                self.brightness = Settings.shared.brightness
                self.objectWillChange.send()
            }
        }
        Settings.shared.addListener(setting: "batteryAutomation") {
            if self.batteryAutomation != Settings.shared.batteryAutomation {
                self.batteryAutomation = Settings.shared.batteryAutomation
                self.objectWillChange.send()
            }
        }
        Settings.shared.addListener(setting: "timerAutomation") {
            if self.timerAutomation != Settings.shared.timerAutomation {
                self.timerAutomation = Settings.shared.timerAutomation
                self.objectWillChange.send()
            }
        }
    }
}

struct BasicSettings: View {
    @ObservedObject var viewModel = BasicSettingsViewModel()
    
    @State private var launchOnLogin = Settings.shared.launchAtLogin
    @State private var brightIntoshOnlyOnBuiltIn = Settings.shared.brightIntoshOnlyOnBuiltIn
    @State private var batteryLevelThreshold = Settings.shared.batteryAutomationThreshold
    @State private var timerAutomationTimeout = Settings.shared.timerAutomationTimeout
    
#if !STORE
    @State private var autoUpdateCheck = Settings.shared.autoUpdateCheck
#endif
    
    
    
    var body: some View {
        VStack(alignment: HorizontalAlignment.leading) {
            Section(header: Text("Brightness").bold()) {
                Toggle("Increased brightness", isOn: $viewModel.brightIntoshActiveToggle)
                Slider(value: $viewModel.brightnessSlider, in: 1.0...getDeviceMaxBrightness()) {
                    Text("Brightness")
                }
                if isDeviceSupported() {
                    Toggle("Don't apply increased brightness to external XDR displays", isOn: $brightIntoshOnlyOnBuiltIn)
                        .onChange(of: brightIntoshOnlyOnBuiltIn) { value in
                            Settings.shared.brightIntoshOnlyOnBuiltIn = value
                        }
                } else {
                    Label("Your device doesn't have a built-in XDR display. Increased brightness can only be enabled for external XDR displays.", systemImage: "exclamationmark.triangle.fill").foregroundColor(Color.yellow)
                }
            }
            Section(header: Text("Automations").bold()) {
                Toggle("Launch on login", isOn: $launchOnLogin)
                    .onChange(of: launchOnLogin) { value in
                        Settings.shared.launchAtLogin = value
                    }
                HStack {
                    Toggle("Disable when battery level drops under", isOn: $viewModel.batteryAutomationToggle)
                    TextField("Battery level threshold", value: $batteryLevelThreshold, format: .percent)
                        .onChange(of: batteryLevelThreshold) { value in
                            if !(0...100 ~= batteryLevelThreshold) {
                                batteryLevelThreshold = max(0, min(batteryLevelThreshold, 100))
                            } else {
                                Settings.shared.batteryAutomationThreshold = value
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 60)
                        .multilineTextAlignment(.center)
                }
                HStack {
                    Toggle("Disable after", isOn: $viewModel.timerAutomationToggle)
                    Picker(selection: $timerAutomationTimeout, label: EmptyView()) {
                        ForEach(Array(stride(from: 10, to: 51, by: 10)), id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                        ForEach(Array(stride(from: 1, to: 5, by: 0.5)), id: \.self) { hours in
                            Text(String(format: "%.1f h", hours)).tag(Int(hours * 60))
                        }
                    }
                    .onChange(of: timerAutomationTimeout) { value in
                        Settings.shared.timerAutomationTimeout = value
                    }
                    .frame(maxWidth: 80)
                }
            }
            Section(header: Text("Shortcuts").bold()) {
                Form {
                    KeyboardShortcuts.Recorder("Toggle increased brightness:", name: .toggleBrightIntosh)
                    KeyboardShortcuts.Recorder("Increase brightness:", name: .increaseBrightness)
                    KeyboardShortcuts.Recorder("Decrease brightness:", name: .decreaseBrightness)
                }
            }
            
#if !STORE
            Section(header: Text("Updates").bold()) {
                Toggle("Check automatically for updates", isOn: $autoUpdateCheck)
                    .onChange(of: autoUpdateCheck) { value in
                        Settings.shared.autoUpdateCheck = value
                    }
                Button("Check for updates") {
                    Settings.shared.updaterController.checkForUpdates(nil)
                }
            }
#endif
        }.frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: 0,
            maxHeight: .infinity,
            alignment: .topLeading
        ).padding()
    }
}

struct Acknowledgments: View {
    var body: some View {
        VStack(alignment: HorizontalAlignment.leading) {
            ScrollView {
                ForEach(acknowledgments) { ack in
                    Text(ack.title).font(.title2)
                    Text(ack.text)
                }
            }
        }.frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: 0,
            maxHeight: .infinity,
            alignment: .topLeading
        ).padding()
    }
}

struct SettingsView: View {
#if STORE
    var title: String = "BrightIntosh SE v\(appVersion)"
#else
    var title: String = "BrightIntosh v\(appVersion)"
#endif
    
    var body: some View {
        VStack {
            Text("Settings").font(.largeTitle)
            TabView {
                BasicSettings().tabItem {
                    Text("General")
                }
                Acknowledgments().tabItem {
                    Text("Acknowledgments")
                }
            }
            Label(title, image: "LogoBordered").imageScale(.small)
        }.padding()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}


final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init() {
        
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        let contentView = SettingsView().frame(width: 500, height: 580)
        
        settingsWindow.contentView = NSHostingView(rootView: contentView)
        settingsWindow.titlebarAppearsTransparent = true
        settingsWindow.titlebarSeparatorStyle = .none
        settingsWindow.center()
        
        super.init(window: settingsWindow)
        settingsWindow.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func windowWillClose(_ notification: Notification) {
        NSApp.stopModal()
    }
}
