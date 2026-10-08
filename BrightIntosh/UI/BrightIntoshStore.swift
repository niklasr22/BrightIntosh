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
    
    var content: some View {
        VStack {
            Label(text, systemImage: style == .info ? "info.circle" : "exclamationmark.triangle")
                .frame(maxWidth: .infinity)
                .transition(.opacity)
        }
        .padding(10)
    }
    
    var body: some View {
        content
            .background(style == .info ? Color.brightintoshBlue : Color("ErrorColor"))
            .clipShape(RoundedRectangle(cornerRadius: 10.0))
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
    
    @State private var isLoading = true
    @State private var loadAttempt = 0
    @State private var isPurchasing = false
    @State private var isRestoringAccess = false
        
    @Environment(\.isUnrestrictedUser) private var isUnrestrictedUser: Bool
    @Environment(\.trial) private var trial: TrialData?

    @State private var showLoadingHelp = false
    
    @State private var fetchingError: String?
    @State private var transactionError: String?
    @State private var transactionNotice: String?

    private var isBusy: Bool { isPurchasing || isRestoringAccess }

    var body: some View {
        VStack {
            if entitlementHandler.isUnrestrictedUser || isUnrestrictedUser {
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
                    if showLoadingHelp {
                        Note(text: String(localized: "The App Store is taking longer than expected. Check your internet connection and try again."))
                    }
                    if let transactionError = transactionError {
                        Note(text: transactionError, style: .error)
                    }
                    if let transactionNotice {
                        Note(text: transactionNotice)
                    }
                    if let fetchingError = fetchingError {
                        Note(text: fetchingError, style: .error)
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
                                .foregroundColor(Color.orange)
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
                            .disabled(isBusy)
                            if isPurchasing { ProgressView() }
                        }
                    } else if isLoading {
                        Spacer()
                        ProgressView()
                            .task(id: loadAttempt) {
                                do {
                                    try await Task.sleep(for: .seconds(6))
                                    guard !Task.isCancelled else { return }
                                    showLoadingHelp = true
                                } catch {}
                            }
                        Spacer()
                    }
                    if fetchingError != nil || showLoadingHelp {
                        Button("Retry") {
                            loadAttempt += 1
                        }
                        .disabled(isBusy)
                    }
                    RestorePurchasesButton(label: String(localized: "Restore In-App Purchase"), action: {
                        await restoreAccess(refreshAppPurchase: false)
                    })
                    .disabled(isBusy)
                    RestorePurchasesButton(label: String(localized: "Revalidate App Purchase"), action: {
                        await restoreAccess(refreshAppPurchase: true)
                    })
                    .disabled(isBusy)
                    HStack {
                        Text("[Privacy Policy](https://brightintosh.de/app_privacy_policy_en.html)")
                        Text("[Terms](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/)")
                    }
                    Spacer()
                }
                .padding(20.0)
            }
        }
        .task(id: loadAttempt) {
            await loadProduct()
        }
    }

    private func loadProduct() async {
        isLoading = true
        showLoadingHelp = false
        fetchingError = nil
        do {
            let products = try await Product.products(for: Products.allCases.map(\.rawValue))
            guard !Task.isCancelled else { return }
            product = products.first { $0.id == Products.unrestrictedBrightIntosh.rawValue }
            if product == nil {
                fetchingError = String(localized: "Unable to load this purchase. Please try again.")
            }
        } catch {
            guard !Task.isCancelled else { return }
            let message = (error as? StoreKitError).map(getStoreKitErrorMessage) ?? error.localizedDescription
            fetchingError = String(localized: LocalizedStringResource("Error while fetching products: \(message)"))
            logger.error("Error while fetching products: \(message)")
        }
        isLoading = false
        showLoadingHelp = false
    }

    private func restoreAccess(refreshAppPurchase: Bool) async {
        guard !isBusy else { return }
        isRestoringAccess = true
        transactionError = nil
        transactionNotice = nil
        defer { isRestoringAccess = false }
        do {
            if !refreshAppPurchase { try await AppStore.sync() }
            let restored = try await entitlementHandler.isUnrestrictedUser(refresh: refreshAppPurchase)
            if !restored {
                transactionNotice = String(localized: "No purchases were found for your Apple Account.")
            }
        } catch {
            let message = (error as? StoreKitError).map(getStoreKitErrorMessage) ?? error.localizedDescription
            transactionError = refreshAppPurchase
                ? String(localized: LocalizedStringResource("Error while revalidating: \(message)"))
                : String(localized: LocalizedStringResource("Error while restoring: \(message)"))
        }
    }

    private func purchase() async {
        guard !isBusy, let product = product else {
            return
        }
        isPurchasing = true
        transactionError = nil
        transactionNotice = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verificationResult):
                try await entitlementHandler.processTransaction(verificationResult)
                transactionError = nil
                fetchingError = nil
            case .userCancelled:
                logger.info("User cancelled purchase of \(product.displayName)")
                transactionError = nil
            case .pending:
                transactionNotice = String(localized: "Purchase is awaiting approval. Access will unlock automatically when it is approved.")
                break
            @unknown default:
                transactionError = String(localized: LocalizedStringResource("An unknown error occurred while purchasing."))
                break
            }
        } catch let error as StoreKitError {
            transactionError = String(localized: LocalizedStringResource("Error while purchasing: \(getStoreKitErrorMessage(error))"))
            logger.error("Error while purchasing: \(getStoreKitErrorMessage(error))")
        } catch {
            transactionError = String(localized: LocalizedStringResource("Error while purchasing: \(error.localizedDescription)"))
            logger.error("Error while purchasing: \(error.localizedDescription)")
        }
    }
    

}

#Preview {
    BrightIntoshStoreView()
        .frame(width: 800, height: 600)
        .environment(\.trial, TrialData(purchaseDate: Date(timeInterval: -1_000_000, since: Date.now), currentDate: Date.now))
        .environment(\.isUnrestrictedUser, false)
}
