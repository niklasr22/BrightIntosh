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
    @State private var isRestoring = false
    
    var body: some View {
        Button(action: {
            isRestoring = true
            Task.detached {
                defer { isRestoring = false }
                try await AppStore.sync()
                _ = await EntitlementHandler.shared.checkAppEntitlements()
            }
        }) {
           Text("Restore Purchases")
               .frame(maxWidth: 220.0)
        }
        .buttonStyle(BrightIntoshButtonStyle(backgroundColor: .gray))
        .disabled(isRestoring)
    }
    
}

#Preview {
    RestorePurchasesButton()
}
