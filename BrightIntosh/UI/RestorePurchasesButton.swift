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
    public let action: () async -> ()
    @State private var isRestoring = false
    
    var body: some View {
        Button(action: {
            isRestoring = true
            Task.detached {
                defer { isRestoring = false }
                await action()
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
