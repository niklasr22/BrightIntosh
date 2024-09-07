//
//  Styles.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 07.09.24.
//


import SwiftUI

struct BrightIntoshButtonStyle: ButtonStyle {
    public var backgroundColor: Color = .brightintoshBlue
    
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .padding(10.0)
            .foregroundColor(.white)
            .background(backgroundColor)
            .brightness(configuration.isPressed ? 0.1 : 0)
            .clipShape(RoundedRectangle(cornerRadius: 25.0))
    }
}

private struct CardModifier: ViewModifier {
    public var backgroundColor: Color
    public var opacity: Double
    
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.black)
            .padding(20.0)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(backgroundColor)
                    .opacity(opacity)
                    .shadow(radius: 3)
            )
    }
}

extension View {
    func translucentCard(backgroundColor: Color = .white, opacity: Double = 0.5) -> some View {
        modifier(CardModifier(backgroundColor: backgroundColor, opacity: opacity))
    }
}
