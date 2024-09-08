//
//  StoreModifier.swift
//  LiMeat
//
//  Created by Niklas Rousset on 10.08.24.
//

import StoreKit
import SwiftUI

struct UserStatusKey: EnvironmentKey {
#if STORE
    static let defaultValue: Bool = false
#else
    static let defaultValue: Bool = true
#endif
}

struct TrialKey: EnvironmentKey {
    static let defaultValue: TrialData? = nil
}

public extension EnvironmentValues {
    var isUnrestrictedUser: Bool {
        get { self[UserStatusKey.self] }
        set { self[UserStatusKey.self] = newValue }
    }
    var trial: TrialData? {
        get { self[TrialKey.self] }
        set { self[TrialKey.self] = newValue }
    }
}

private struct UserStatusTaskModifier: ViewModifier {
    @State var unrestrictedUser = false
    @State var trial: TrialData? = nil
    
    @ObservedObject var entitlementHandler = EntitlementHandler.shared
    
    func body(content: Content) -> some View {
        content
            .task {
#if STORE
                _ = await EntitlementHandler.shared.isUnrestrictedUser()
                do {
                    trial = try await TrialData.getTrialData()
                } catch {}
#endif
            }
            .onReceive(entitlementHandler.$isUnrestrictedUser, perform: { isUnrestricted in
                unrestrictedUser = isUnrestricted
            })
            .environment(\.isUnrestrictedUser, unrestrictedUser)
            .environment(\.trial, trial)
    }
}


extension View {
    func userStatusTask() -> some View {
        modifier(UserStatusTaskModifier())
    }
}
