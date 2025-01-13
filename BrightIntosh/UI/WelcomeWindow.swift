//
//  WelcomeWindow.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 12.09.23.
//

import SwiftUI

struct IntroView: View {
    var supportedDevice: Bool = false
    var onAccept: () -> Void
    
    @Environment(\.isUnrestrictedUser) private var isUnrestrictedUser: Bool
    
    var body: some View {
        VStack(alignment: .center, spacing: 10.0) {
            VStack(alignment: .leading, spacing: 10.0) {
                if !supportedDevice {
                    VStack {
                        Label(
                            title: {
                                Text("Unfortunately your device is currently not supported by BrightIntosh.")
                            },
                            icon: {
                                Image(systemName: "exclamationmark.triangle")
                            }
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .translucentCard(backgroundColor: .yellow)
                }
                VStack(spacing: 10.0) {
                    HStack(alignment: .center) {
                        Spacer()
                        Image(systemName: "1.circle")
                            .resizable()
                            .frame(width: 25.0, height: 25.0)
                            .foregroundColor(.brightintoshBlue)
                        Spacer()
                        Spacer()
                        Image(systemName: "2.circle")
                            .resizable()
                            .frame(width: 25.0, height: 25.0)
                            .foregroundColor(.brightintoshBlue)
                        Spacer()
                        Spacer()
                        Image(systemName: "3.circle")
                            .resizable()
                            .frame(width: 25.0, height: 25.0)
                            .foregroundColor(.brightintoshBlue)
                        Spacer()
                        
                    }
                    HStack(alignment: .top) {
                        Spacer()
                        Text("Click the \(Image(systemName: "sun.max.circle")) icon in your menu bar")
                            .multilineTextAlignment(.center)
                            .font(.title3)
                            .bold()
                            .frame(maxWidth: .infinity, alignment: .top)
                        Spacer()
                        Text("Click *Activate*")
                            .multilineTextAlignment(.center)
                            .font(.title3)
                            .bold()
                            .frame(maxWidth: .infinity, alignment: .top)
                        Spacer()
                        Text("Enjoy the extra brightness")
                            .multilineTextAlignment(.center)
                            .font(.title3)
                            .bold()
                            .frame(maxWidth: .infinity, alignment: .top)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, idealHeight: 0, maxHeight: 110.0)
                .translucentCard()
                if supportedDevice {
                    Label(
                        "BrightIntosh can shift your brightness range to higher values. The brightness slider in this app controls how much you shift this range. You can still use your brightness keys to control the brightness.",
                        systemImage: "info.circle"
                    )
                        .frame(maxWidth: .infinity)
                        .translucentCard()
                    
                    Label("You can also use the \(Image(systemName: "magnifyingglass")) Spotlight Search to open the settings window by searching \"BrightIntosh Settings\"",
                          systemImage: "info.circle")
                        .frame(maxWidth: .infinity)
                        .translucentCard()
                }
                
                VStack(alignment: .leading, spacing: 10.0) {
                    Text("Disclaimer")
                        .bold()
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("BrightIntosh is designed to be safe for your MacBook Pro and does not bypass the operating system's protections. BrightIntosh is open source software and therefore comes with no warranties, so use it at your own risk.")
                        .lineLimit(nil)
                }
                .foregroundStyle(.black)
                .translucentCard()
            }
            
            Spacer()
            
            Button(action: onAccept) {
                Text("Accept")
            }
            .buttonStyle(BrightIntoshButtonStyle())
        }
    }
}

struct WelcomeStoreView: View {
    var onContinue: () -> Void
    var trial: TrialData
    
    @Environment(\.isUnrestrictedUser) private var isUnrestrictedUser: Bool
    
    var body: some View {
        VStack {
            VStack {
                if !trial.stillEntitled() {
                    Text("Your trial has expired")
                        .font(.largeTitle)
                        .bold()
                } else {
                    Text("Unleash the Brightness!")
                        .font(.largeTitle)
                        .bold()
                }
            }
            .frame(maxWidth: .infinity)
            .translucentCard()
            
            VStack {
                BrightIntoshStoreView(showLogo: false)
            }
            .frame(maxWidth: .infinity)
            .translucentCard()
            
            Spacer()
            
            if !isUnrestrictedUser && trial.stillEntitled() && trial.getRemainingDays() > 0 {
                Button(action: onContinue) {
                    Text("Start your free \(trial.getRemainingDays()) day trial")
                }
                .buttonStyle(BrightIntoshButtonStyle())
            }
        }
    }
}

struct WelcomeView: View {
    
    var supportedDevice: Bool = false
    var closeWindow: () -> Void
    
    @State var showStore = false
   
    @Environment(\.trial) private var trial: TrialData?
    @Environment(\.isUnrestrictedUser) private var isUnrestrictedUser: Bool
    
    var body: some View {
        VStack {
            HStack {
                Image("LogoBorderedHighRes")
                    .resizable()
                    .frame(width: 100, height: 100)
                    .aspectRatio(contentMode: .fit)
                Text("BrightIntosh")
                    .font(.largeTitle)
                    .foregroundColor(.brightintoshBlue)
                    .bold()
            }
            Spacer()
            if !showStore {
                IntroView(
                    supportedDevice: supportedDevice, 
                    onAccept: {
#if STORE
                        if isUnrestrictedUser {
                            closeWindow()
                            return
                        }
                        showStore = true
#else
                        closeWindow()
#endif
                    }
                )
            } else {
                if let trial = trial {
                    WelcomeStoreView(onContinue: closeWindow, trial: trial)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(20.0)
        .background(LinearGradient.brightIntoshBackground)
    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView(closeWindow: {() in })
            .frame(width: 580, height: 680)
    }
}

final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    init(supportedDevice: Bool) {
        
        let welcomeWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 660),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        let contentView = WelcomeView(supportedDevice: supportedDevice, closeWindow: welcomeWindow.close).frame(width: 550, height: 660)
            .userStatusTask()
        
        welcomeWindow.contentView = NSHostingView(rootView: contentView)
        welcomeWindow.titlebarAppearsTransparent = true
        welcomeWindow.titlebarSeparatorStyle = .none
        welcomeWindow.titleVisibility = .hidden
        welcomeWindow.styleMask = [.closable, .titled, .fullSizeContentView]
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
