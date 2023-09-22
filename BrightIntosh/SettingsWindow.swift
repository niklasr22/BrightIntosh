//
//  SettingsWindow.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 17.09.23.
//

import SwiftUI

struct BasicSettings: View {
    @State private var increasedBrightness = false
    @State private var launchOnLogin = false
    @State private var autoDisableOnLowBattery = false
    
    @State private var input = ""
    @State private var brightness = 1.0
    
    var body: some View {
        VStack(alignment: HorizontalAlignment.leading) {
            Section(header: Text("Brightness").bold()) {
                Toggle("Increased brightness", isOn: $increasedBrightness)
                Slider(value: $brightness) {
                    Text("Brightness")
                }
            }
            /* Section(header: Text("Automations").bold()) {
                Toggle("Launch on login", isOn: $launchOnLogin)
                // Toggle("Automatically disable increased brightness when battery level drops", isOn: $autoDisableOnLowBattery)
                // Toggle("Automatically toggle increased brightness depending on the envrionment's brightness", isOn: $autoDisableOnLowBattery)
            } */
            /*Section(header: Text("Shortcut").bold()) {
                TextField("Toggle increased brightness", text: $input)
            }*/
            Spacer()
        }.padding()
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
        }.padding()
    }
}

struct SettingsWindow: View {
    var title: String = "BrightIntosh v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)!
    
    var body: some View {
        VStack {
            TabView {
                BasicSettings().tabItem {
                    Text("General")
                }
                AdvancedSettings().tabItem {
                    Text("Advanced")
                }
            }
            Label(title, image: "LogoBordered").imageScale(.small)
        }.padding()
    }
}

struct SettingsWindow_Previews: PreviewProvider {
    static var previews: some View {
        SettingsWindow()
    }
}
