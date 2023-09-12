//
//  WelcomeWindow.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 12.09.23.
//

import SwiftUI


struct WelcomeWindow: View {
    var closeWindow: () -> Void
    
    var body: some View {
        VStack(alignment: HorizontalAlignment.center, spacing: 10.0) {
            Image("Logo").resizable()
                .frame(width: 200, height: 200)
                .aspectRatio(contentMode: .fit)
            Text("Welcome to BrightIntosh!").font(Font.title)
            VStack (alignment: HorizontalAlignment.leading, spacing: 10.0) {
                Text("Disclaimer:").font(Font.headline)
                Text("BrightIntosh is designed to be safe for your computer. It will not harm your hardware, as it does not bypass the operating system's protections.")
                    .lineLimit(5)
                
                
                Text("How to use BrightIntosh:").font(Font.headline)
                Text("When the app is running you will see a sun icon in your menu bar that provides everything you need to use BrightIntosh.")
                    .lineLimit(nil)
            }
            Spacer()
            Button("Alright") {
                closeWindow()
            }
            .buttonStyle(.borderedProminent)
        }.padding()
    }
}

struct WelcomeWindow_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeWindow(closeWindow: {() in })
    }
}
