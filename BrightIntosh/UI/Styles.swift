//
//  Styles.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 07.09.24.
//


import SwiftUI

extension Color {
    public static let brightintoshBlue = Color(red: 0.25, green: 0.67, blue: 0.79)
    public static let brightintoshBluePressed = Color(red: 0.36, green: 0.74, blue: 0.84)
}

extension LinearGradient {
    public static let brightIntoshBackground = LinearGradient(colors: [Color(red: 0.75, green: 0.89, blue: 0.97), Color(red: 0.67, green: 0.87, blue: 0.93)], startPoint: .topLeading, endPoint: .bottom)
}

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
    var backgroundColor: Color
    var opacity: Double
    
    @ViewBuilder
    func body(content: Content) -> some View {
        #if swift(>=6.2)
        if #available(macOS 26.0, *) {
            content
                .foregroundStyle(.black)
                .padding(20.0)
                .glassEffect(in: .rect(cornerRadius: 10.0))
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    // encapsulate the fallback to avoid duplicating the styling code
    @ViewBuilder
    private func fallback(_ content: Content) -> some View {
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
