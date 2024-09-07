//
//  BrightIntoshStore.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 06.09.24.
//

import SwiftUI
import StoreKit
import OSLog

struct BrightIntoshStoreView: View {
    private let logger = Logger(
        subsystem: "Settings View",
        category: "Store"
    )
    @ObservedObject private var storeManager = StoreManager()
    
    @Environment(\.isUnrestrictedUser) private var isUnrestrictedUser: Bool
    
    var body: some View {
        VStack {
            if isUnrestrictedUser {
                Spacer()
                Text("You already have access to BrightIntosh. Enjoy the brightness!")
                Spacer()
            } else if #available(macOS 14.0, *) {
                StoreView(ids: [Products.unrestrictedBrightIntosh]) { product in
                    Image("LogoBorderedHighRes").resizable().scaledToFit()
                }
                .storeButton(.hidden, for: .cancellation)
                .storeButton(.visible, for: .restorePurchases, .signIn)
            } else {
                VStack {
                    Spacer()
                    if let product = storeManager.products.first {
                        VStack {
                            Image("LogoBorderedHighRes").resizable().scaledToFit().frame(height: 90.0)
                            Text(product.localizedTitle)
                            Button(action: {
                                storeManager.purchase(product: product)
                            }) {
                                Text("Buy \(product.priceLocale.currencySymbol ?? "$")\(product.price)")
                                    .frame(maxWidth: 220.0)
                            }
                            .buttonStyle(BrightIntoshButtonStyle())
                        }
                    } else {
                        ProgressView()
                        Spacer()
                    }
                    Button(action: {
                        storeManager.restorePurchases()
                    }) {
                        
                        Text("Restore Purchases")
                            .frame(maxWidth: 220.0)
                    }
                    .buttonStyle(BrightIntoshButtonStyle(backgroundColor: .gray))
                    Spacer()
                }
                .padding(20.0)
            }
        }
    }
}

#Preview {
    BrightIntoshStoreView()
        .frame(width: 800, height: 600)
}
