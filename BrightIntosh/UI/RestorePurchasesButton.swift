//
//  RestorePurchasesButton.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 04.07.24.
//

import Foundation
import SwiftUI
import StoreKit

struct RestorePurchasesButton: View {
    public let label: String
    public let action: @MainActor () async -> ()
    @State private var isRestoring = false
    
    var body: some View {
        Button(action: {
            isRestoring = true
            Task {
                await action()
                await MainActor.run {
                    isRestoring = false
                }
            }
        }) {
           Text(label)
               .frame(maxWidth: 220.0)
        }
        .buttonStyle(BrightIntoshButtonStyle(backgroundColor: .gray))
        .disabled(isRestoring)
    }
    
}

#Preview {
    RestorePurchasesButton(label: "Restore Purchases", action: {})
}
