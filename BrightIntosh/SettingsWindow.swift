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

final class BasicSettingsViewModel: NSObject, ObservableObject {
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

    @objc private let settings: Settings = Settings.shared
    private var observationBrightIntoshActive: NSKeyValueObservation?
    private var observationBrightness: NSKeyValueObservation?
    
    override init() {
        super.init()
        observationBrightIntoshActive = observe(\.settings.brightintoshActive, options: [.old, .new]) {
            object, change in
            if self.brightIntoshActive != Settings.shared.brightintoshActive {
                self.brightIntoshActive = Settings.shared.brightintoshActive
                self.objectWillChange.send()
            }
        }
        observationBrightness = observe(\.settings.brightness, options: [.old, .new]) {
            object, change in
            if self.brightness != Settings.shared.brightness {
                self.brightness = Settings.shared.brightness
                self.objectWillChange.send()
            }
        }
    }
}

struct BasicSettings: View {
    @ObservedObject var viewModel = BasicSettingsViewModel()
    
    @State private var launchOnLogin = Settings.shared.launchAtLogin
    @State private var autoDisableOnLowBattery = false
#if !STORE
    @State private var autoUpdateCheck = Settings.shared.autoUpdateCheck
#endif
    
    var body: some View {
        VStack(alignment: HorizontalAlignment.leading) {
            Section(header: Text("Brightness").bold()) {
                Toggle("Increased brightness", isOn: $viewModel.brightIntoshActiveToggle)
                Slider(value: $viewModel.brightnessSlider, in: 1.0...1.6) {
                    Text("Brightness")
                }
            }
            Section(header: Text("Automations").bold()) {
                Toggle("Launch on login", isOn: $launchOnLogin)
                    .onChange(of: launchOnLogin) { value in
                        Settings.shared.launchAtLogin = value
                    }
                // Toggle("Automatically disable increased brightness when battery level drops", isOn: $autoDisableOnLowBattery)
                // Toggle("Automatically toggle increased brightness depending on the envrionment's brightness", isOn: $autoDisableOnLowBattery)
            }
            Section(header: Text("Shortcut").bold()) {
                KeyboardShortcuts.Recorder("Toggle increased brightness:", name: .toggleBrightIntosh)
                KeyboardShortcuts.Recorder("Increase brightness:", name: .increaseBrightness)
                KeyboardShortcuts.Recorder("Decrease brightness:", name: .decreaseBrightness)
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



struct AdvancedSettings: View {
    
    @State private var activeWindowHighlight = false
    @State private var overlayTechnique = false
    
    var body: some View {
        VStack(alignment: HorizontalAlignment.leading) {
            //Toggle("Highlight the active window with increased brightness", isOn: $activeWindowHighlight)
            Toggle(isOn: $overlayTechnique) {
                Text("Increase brightness using an overlay technique.")
                Label("This may show more accurate colors but the increased brightness won't be available when using Mission Control or switching Spaces. The window selection tool of the screenshot application won't be able to focus any other window than the overlay.", systemImage: "exclamationmark.triangle.fill").foregroundColor(Color.yellow)
            }
            Spacer()
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
                /*AdvancedSettings().tabItem {
                    Text("Advanced")
                }*/
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
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        let contentView = SettingsView().frame(width: 500, height: 500)
        
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
