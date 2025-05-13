//
//  BrightIntoshStore.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 06.09.24.
//

import SwiftUI
import StoreKit
import OSLog

enum NoteStyle {
    case info
    case error
}

struct Note: View {
    var text: String
    var style: NoteStyle = .info
    
    var body: some View {
        VStack {
            Label(text, systemImage: style == .info ? "info.circle" : "exclamationmark.triangle")
                .frame(maxWidth: .infinity)
        }
        .padding(10)        
        .background(style == .info ? Color.brightintoshBlue : Color.red)
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
    
    @ObservedObject private var entitlementHandler = EntitlementHandler.shared
    
    @State private var product: Product?
    
    @State var purchaseCompleted = false
        
    @Environment(\.isUnrestrictedUser) private var isUnrestrictedUser: Bool
    @Environment(\.trial) private var trial: TrialData?

    @State private var showRestartNoteDueToSpinner = false
    
    @State private var transactionError: String?

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
                    if showRestartNoteDueToSpinner {
                        Note(text: "There seems to be an issue with the store connection. Please check your internet connection and try restarting your MacBook.", style: .error)
                    }
                    if let transactionError = transactionError {
                        Note(text: transactionError, style: .error)
                    }
                    Spacer()
                    if let product = product {
                        VStack {
                            if showLogo {
                                Image("LogoBorderedHighRes").resizable().scaledToFit().frame(height: 90.0)
                            }
                            Text(product.displayName)
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
                                Task {
                                    await self.purchase()
                                }
                            }) {
                                Text("Buy \(product.displayPrice)")
                                    .frame(maxWidth: 220.0)
                            }
                            .buttonStyle(BrightIntoshButtonStyle())
                        }
                    } else {
                        Spacer()
                        ProgressView()
                            .onAppear {
                                Task {
                                    await delayNotLoadingRestartNote()
                                }
                            }
                        Spacer()
                    }
                    RestorePurchasesButton(label: "Restore In-App Purchase", action: {
                        do {
                            try await AppStore.sync()
                            _ = try await EntitlementHandler.shared.isUnrestrictedUser()
                        } catch {
                            transactionError = String(localized: LocalizedStringResource("Error while restoring: \(error.localizedDescription)"))
                        }
                    })
                    RestorePurchasesButton(label: "Revalidate App Purchase", action: {
                        do {
                            _ = try await EntitlementHandler.shared.isUnrestrictedUser(refresh: true)
                        } catch {
                            transactionError = String(localized: LocalizedStringResource("Error while revalidating: \(error.localizedDescription)"))
                        }
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
            showRestartNoteDueToSpinner = false
        }.task {
            do {
                let availableProducts = Products.allCases.map { $0.rawValue }
                let products = try await Product.products(for: availableProducts)
                if let unrestrictedBrightIntosh = products.first(where: { $0.id == Products.unrestrictedBrightIntosh.rawValue }) {
                    product = unrestrictedBrightIntosh
                }
                transactionError = nil
            } catch {
                transactionError = String(localized: LocalizedStringResource("Error while fetching products: \(error.localizedDescription)"))
                logger.error("Error while fetching products: \(error.localizedDescription)")
            }
        }
    }
    
    private func purchase() async {
        guard let product = product else {
            return
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verificationResult):
                if try await entitlementHandler.verifyEntitlement(transaction: verificationResult) {
                    entitlementHandler.setRestrictionState(isUnrestricted: true)
                }
            case .userCancelled:
                logger.info("User cancelled purchase of \(product.displayName)")
            case .pending:
                break
            @unknown default:
                break
            }
            transactionError = nil
        } catch {
            logger.error("Error while purchasing: \(error.localizedDescription)")
            transactionError = String(localized: LocalizedStringResource("Error while purchasing: \(error.localizedDescription)"))
        }
    }
    
    private func delayNotLoadingRestartNote() async {
        do {
            try await Task.sleep(nanoseconds: 6_000_000_000)
        } catch {
            return
        }
        withAnimation {
            if product == nil {
                showRestartNoteDueToSpinner = true
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
