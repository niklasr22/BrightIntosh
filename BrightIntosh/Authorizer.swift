//
//  Authorizer.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 21.06.25.
//

import Foundation
import Combine

public enum AuthorizationStatus: Comparable, Sendable {
    case unauthorized
    case pending
    case authorized
    case authorizedUnlimited
}

@MainActor
public class Authorizer: ObservableObject {
    static let shared = Authorizer()
    
    @Published var status: AuthorizationStatus = .pending
    
    private var authorizationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
#if STORE
        startAuthorizationTimer()
        
        
        EntitlementHandler.shared.$status.sink { newStatus in
            self.update(purchaseStatus: newStatus, trialStatus: TrialHandler.shared.status)
        }.store(in: &cancellables)
        
        TrialHandler.shared.$status.sink { newStatus in
            self.update(purchaseStatus: EntitlementHandler.shared.status, trialStatus: newStatus)
        }.store(in: &cancellables)
        
#else
        status = .authorizedUnlimited
#endif
    }
    
    func update(purchaseStatus: AuthorizationStatus, trialStatus: AuthorizationStatus) {
        status = max(purchaseStatus, trialStatus)
        print("Auth status updated: \(status)")
        if authorizationTimer != nil && status == .authorizedUnlimited {
            // Attempt authorization check until unlimited state is reached
            stopAuthorizationTimer()
        }
    }
    
    func isAllowed() -> Bool {
        return status > .unauthorized
    }
    
    func startAuthorizationTimer() {
        // Check authorization every 5min
        authorizationTimer = Timer(timeInterval: 300, repeats: true, block: {t in
            print("Run Auth Check")
            Task { @MainActor in
                try? await ValidationCoordinator.shared.validateAccess()
            }
        })
        authorizationTimer?.fire()
        RunLoop.main.add(self.authorizationTimer!, forMode: RunLoop.Mode.common)
    }
    
    func stopAuthorizationTimer() {
        print("Auth check done, stopping timer")
        if authorizationTimer == nil {
            return
        }
        self.authorizationTimer?.invalidate()
        self.authorizationTimer = nil
    }
}


public actor ValidationCoordinator {
    static let shared = ValidationCoordinator()
    private var currentValidationTask: Task<(), Never>?
    private let timeoutDuration: TimeInterval = 5.0
    
    func validateAccess() async throws {
        // If there's already a validation in progress, wait for its result
        if currentValidationTask != nil {
            return
        }
        
        // Create new validation task with timeout
        let task = Task {
            defer { currentValidationTask = nil }
            async let entitlement = EntitlementHandler.shared.isUnrestrictedUser()
            async let trial = TrialHandler.shared.updateTrialState()
            do {
                _ = try await entitlement
                _ = await trial
            } catch {
                print("Validation failed: \(error)")
            }
        }
        
        currentValidationTask = task
        await task.value
    }
}
