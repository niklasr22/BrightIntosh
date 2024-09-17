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
                                    .multilineTextAlignment(.center)
                            } else {
                                Text("Unlock unrestricted access to BrightIntosh")
                                    .font(.title2)
                                    .multilineTextAlignment(.center)
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
                        Button(action: {
                            storeManager.fetchProducts()
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        Spacer()
                    }
                    RestorePurchasesButton(label: "Restore In-App Purchase", action: {
                        do {
                            try await AppStore.sync()
                            _ = await EntitlementHandler.shared.checkAppEntitlements()
                        } catch {
                            print("Error while syncing")
                        }
                    })
                    RestorePurchasesButton(label: "Revalidate App Purchase", action: {
                        _ = await EntitlementHandler.shared.checkAppEntitlements(refresh: true)
                    })
                    HStack {
                        Text("[Privacy Policy](https://brightintosh.de/app_privacy_policy_en.html)")
                        Text("[Terms](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/)")
                    }
                    Spacer()
                }
                .onReceive(entitlementHandler.$isUnrestrictedUser, perform: { isUnrestrictedUser in
                    //purchaseCompleted = isUnrestrictedUser
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
        .environment(\.isUnrestrictedUser, false)
}
