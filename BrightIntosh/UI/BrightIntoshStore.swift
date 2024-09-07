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
    public var showLogo: Bool = true
    public var showTrialExpiredWarning: Bool = true
    
    private let logger = Logger(
        subsystem: "Settings View",
        category: "Store"
    )
    @ObservedObject private var storeManager = StoreManager()
    @ObservedObject private var entitlementHandler = EntitlementHandler.shared
    @State var purchaseCompleted = false
        
    @Environment(\.isUnrestrictedUser) private var isUnrestrictedUser: Bool
    @Environment(\.trial) private var trial: TrialData?
    
    var body: some View {
        VStack {
            if purchaseCompleted || isUnrestrictedUser {
                Spacer()
                if showLogo {
                    Image("LogoBorderedHighRes").resizable().scaledToFit().frame(height: 90.0)
                }
                Text("You have access to BrightIntosh.\nEnjoy the brightness!")
                    .multilineTextAlignment(.center)
                    .font(.title)
                Spacer()
            } else if #available(macOS 15.0, *) {
                StoreView(ids: [Products.unrestrictedBrightIntosh]) { product in
                }
                .storeButton(.hidden, for: .cancellation)
                .storeButton(.visible, for: .restorePurchases, .signIn)
                .onInAppPurchaseCompletion(perform: { _,_ in
                    Task {
                        _ = await EntitlementHandler.shared.checkAppEntitlements()
                    }
                })
            } else {
                VStack {
                    Spacer()
                    if let product = storeManager.products.first {
                        VStack {
                            if showLogo {
                                Image("LogoBorderedHighRes").resizable().scaledToFit().frame(height: 90.0)
                            }
                            Text(product.localizedTitle)
                                .bold()
                                .font(.title)
                            
                            if showTrialExpiredWarning && trial != nil && !trial!.stillEntitled() {
                                Text("Your trial has expired. Unlock unrestricted access to BrightIntosh")
                                    .font(.title2)
                            } else {
                                Text("Unlock unrestricted access to BrightIntosh")
                                    .font(.title2)
                            }
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
                    RestorePurchasesButton()
                    Spacer()
                }
                .onReceive(entitlementHandler.$isUnrestrictedUser, perform: { isUnrestrictedUser in
                    purchaseCompleted = isUnrestrictedUser
                })
                .padding(20.0)
            }
        }
    }
}

#Preview {
    BrightIntoshStoreView()
        .frame(width: 800, height: 600)
        .environment(\.trial, TrialData(purchaseDate: Date(timeInterval: -1_000_000, since: Date.now), currentDate: Date.now))
}
