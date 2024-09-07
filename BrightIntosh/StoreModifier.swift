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

public extension EnvironmentValues {
    var isUnrestrictedUser: Bool {
        get { self[UserStatusKey.self] }
        set { self[UserStatusKey.self] = newValue }
    }
}

private struct UserStatusTaskModifier: ViewModifier {
    @State var unrestrictedUser = false
    
    func body(content: Content) -> some View {
        content
            .task {
#if STORE
                unrestrictedUser = await StoreHandler.shared.isUnrestrictedUser()
#endif
            }
            .environment(\.isUnrestrictedUser, unrestrictedUser)
    }
}


extension View {
    func userStatusTask() -> some View {
        modifier(UserStatusTaskModifier())
    }
}
