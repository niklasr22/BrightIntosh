//
//  BrightIntoshStore.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 06.09.24.
//

import SwiftUI
import StoreKit
import OSLog

struct InfoNote: View {
    var infoText: LocalizedStringKey
    var body: some View {
        VStack {
            Label(infoText, systemImage: "info.circle")
        }
        .padding(10)
        .background(Color.brightintoshBlue)
        .clipShape(RoundedRectangle(cornerRadius: 10.0))
        .transition(.opacity)
    }
}

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

    @State private var showRestartNoteDueToSpinner = false
    
    @State private var restoreAttempts = 0

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
                    if restoreAttempts >= 3 || showRestartNoteDueToSpinner {
                        InfoNote(infoText: "There seems to be an issue with the store connection. Please check your internet connection or try restarting you MacBook.")
                    }
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
                            if !isDeviceSupported() {
                                Label(
                                    "Your device doesn't have a built-in XDR display. Increased brightness can only be enabled for external XDR displays.",
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                .foregroundColor(Color.yellow)
                                .frame(maxWidth: 400.0)
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
                        Spacer()
                        ProgressView()
                            .task {
                                await delayNotLoadingRestartNote()
                            }
                        Spacer()
                    }
                    RestorePurchasesButton(label: "Restore In-App Purchase", action: {
                        do {
                            try await AppStore.sync()
                            _ = await EntitlementHandler.shared.isUnrestrictedUser()
                        } catch {
                            print("Error while syncing")
                        }
                        restoreAttempts += 1
                    })
                    RestorePurchasesButton(label: "Revalidate App Purchase", action: {
                        _ = await EntitlementHandler.shared.isUnrestrictedUser(refresh: true)
                        restoreAttempts += 1
                    })
                    HStack {
                        Text("[Privacy Policy](https://brightintosh.de/app_privacy_policy_en.html)")
                        Text("[Terms](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/)")
                    }
                    Spacer()
                }
                .onReceive(entitlementHandler.$isUnrestrictedUser, perform: { isUnrestrictedUser in
                    purchaseCompleted = isUnrestrictedUser
                })
                .padding(20.0)
            }
        }.onAppear {
            restoreAttempts = 0
            showRestartNoteDueToSpinner = false
        }
    }
    
    private func delayNotLoadingRestartNote() async {
        try? await Task.sleep(nanoseconds: 6_000_000_000)
        withAnimation {
            showRestartNoteDueToSpinner = true
        }
    }
}

#Preview {
    BrightIntoshStoreView()
        .frame(width: 800, height: 600)
        .environment(\.trial, TrialData(purchaseDate: Date(timeInterval: -1_000_000, since: Date.now), currentDate: Date.now))
        .environment(\.isUnrestrictedUser, false)
}
