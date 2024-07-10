//
//  RestoringView.swift
//  LiMeat
//
//  Created by Niklas Rousset on 04.07.24.
//

import Foundation
import SwiftUI
import StoreKit

struct RestorePurchasesButton: View {
    @State private var isRestoring = false
    
    var body: some View {
        Button("Restore Purchases") {
            isRestoring = true
            Task.detached {
                defer { isRestoring = false }
                try await AppStore.sync()
            }
        }
        .disabled(isRestoring)
    }
    
}

#Preview {
    RestorePurchasesButton()
}
