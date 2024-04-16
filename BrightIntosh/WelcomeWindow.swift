//
//  WelcomeWindow.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 12.09.23.
//

import SwiftUI


struct WelcomeView: View {
    
    var supportedDevice: Bool = false
    var closeWindow: () -> Void
    
    var body: some View {
        VStack(alignment: HorizontalAlignment.center, spacing: 10.0) {
            Image("LogoBorderedHighRes")
                .resizable()
                .frame(width: 200, height: 200)
                .aspectRatio(contentMode: .fit)
            Text("Welcome to BrightIntosh!").font(Font.title)
            VStack (alignment: HorizontalAlignment.leading, spacing: 10.0) {
                Text("Disclaimer:").font(Font.headline)
                Text("BrightIntosh is designed to be safe for your MacBook Pro and does not bypass the operating system's protections. BrightIntosh is open source software and therefore comes with no warranties, so use it at your own risk.")
                    .lineLimit(5)
                Text("How to use BrightIntosh:").font(Font.headline)
                Text("When the app is running you will see a sun icon in your menu bar that provides everything you need to use BrightIntosh.")
                    .lineLimit(nil)
                if !supportedDevice {
                    Label("Unfortunately your device is currently not supported by BrightIntosh.", systemImage:  "exclamationmark.triangle")
                        .foregroundStyle(.yellow)
                }
            }
            Spacer()
            Button("Accept") {
                closeWindow()
            }
            .buttonStyle(.borderedProminent)
        }.padding()
    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView(closeWindow: {() in })
    }
}

final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    init(supportedDevice: Bool) {
        
        let welcomeWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        let contentView = WelcomeView(supportedDevice: supportedDevice, closeWindow: welcomeWindow.close).frame(width: 500, height: 480)
        
        welcomeWindow.contentView = NSHostingView(rootView: contentView)
        welcomeWindow.titlebarAppearsTransparent = true
        welcomeWindow.titlebarSeparatorStyle = .none
        welcomeWindow.center()
        
        super.init(window: welcomeWindow)
        welcomeWindow.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        window?.level = .statusBar
    }
    
    func windowWillClose(_ notification: Notification) {
        NSApp.stopModal()
    }
}
