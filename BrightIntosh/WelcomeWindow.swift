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
    
    @State var acceptedDisclaimer = false
    
    @State var trial: TrialData?
    
    @Environment(\.isUnrestrictedUser) private var isUnrestrictedUser: Bool
    
    var body: some View {
        VStack {
            if !acceptedDisclaimer {
                VStack(alignment: .center, spacing: 10.0) {
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
                    VStack(alignment: .leading, spacing: 10.0) {
                        if !supportedDevice {
                            VStack {
                                Label(
                                    title:{
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
                        VStack(alignment: .leading, spacing: 10.0) {
                            HStack {
                                VStack(spacing: 10.0) {
                                    Image(systemName: "1.circle")
                                        .resizable()
                                        .frame(width: 25.0, height: 25.0)
                                        .foregroundColor(.brightintoshBlue)
                                    Text("Click the \(Image(systemName: "sun.max.circle")) icon in your menu bar")
                                        .multilineTextAlignment(.center)
                                        .font(.title3)
                                        .bold()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                Spacer()
                                VStack(spacing: 10.0) {
                                    Image(systemName: "2.circle")
                                        .resizable()
                                        .frame(width: 25.0, height: 25.0)
                                        .foregroundColor(.brightintoshBlue)
                                    Text("Click *Activate*")
                                        .multilineTextAlignment(.center)
                                        .font(.title3)
                                        .bold()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                Spacer()
                                VStack(spacing: 10.0) {
                                    Image(systemName: "3.circle")
                                        .resizable()
                                        .frame(width: 25.0, height: 25.0)
                                        .foregroundColor(.brightintoshBlue)
                                    Text("Enjoy the extra brightness")
                                        .multilineTextAlignment(.center)
                                        .font(.title3)
                                        .bold()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                Spacer()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: 90.0)
                        .translucentCard()
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
                    Button(action: {
                        if isUnrestrictedUser {
                            closeWindow()
                            return
                        }
                        
                        acceptedDisclaimer = true
                    }) {
                        Text("Accept")
                    }
                    .buttonStyle(BrightIntoshButtonStyle())
                }
                .padding(20.0)
            } else {
                VStack {
                    if trial == nil || !trial!.stillEntitled() {
                        Text("Did you enjoy the free trial?")
                            .foregroundColor(.brightintoshBlue)
                            .font(.largeTitle)
                            .bold()
                    } else {
                        Text("Unleash the Brightness")
                            .foregroundColor(.brightintoshBlue)
                            .font(.largeTitle)
                            .bold()
                    }
                    Text("Purchase your unrestricted BrightIntosh membership")
                        .font(.title2)
                        .foregroundColor(.brightintoshBlue)
                    VStack {
                        BrightIntoshStoreView()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.black)
                    .padding(20.0)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white)
                            .opacity(0.5)
                            .shadow(radius: 3)
                    )
                    if trial != nil && trial!.stillEntitled() && trial!.getRemainingDays() > 0 {
                        Button(action: {
                            closeWindow()
                        }) {
                            Text("Continue your free \(trial!.getRemainingDays()) day trial")
                        }
                        .buttonStyle(BrightIntoshButtonStyle())
                    }
                }
                .padding(20.0)
            }
        }
        .background(LinearGradient(colors: [Color(red: 0.75, green: 0.89, blue: 0.97), Color(red: 0.67, green: 0.87, blue: 0.93)], startPoint: .topLeading, endPoint: .bottom))
        .task {
            do {
                trial = try await TrialData.getTrialData()
                trial = TrialData(purchaseDate: Date.now, currentDate: Date.now)
            } catch {
                print("Could not determine trial state")
            }
        }
    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView(closeWindow: {() in })
            .frame(width: 550, height: 550)
    }
}

final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    init(supportedDevice: Bool) {
        
        let welcomeWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 550),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        let contentView = WelcomeView(supportedDevice: supportedDevice, closeWindow: welcomeWindow.close).frame(width: 550, height: 550)
        
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
