//
//  IncompatibleAppsMonitor.swift
//  BrightIntosh
//
//  Created by Cursor on 26.05.26.
//

import Cocoa

@MainActor
final class IncompatibleAppsMonitor {
    private let noticePresenter = IncompatibleAppsNoticePresenter()
    
    init() {
        BrightIntoshSettings.shared.addListener(setting: "brightintoshActive") {
            if BrightIntoshSettings.shared.brightintoshActive {
                self.noticePresenter.scheduleIfNeeded()
            }
        }
        
        BrightIntoshSettings.shared.addListener(setting: "showIncompatibleAppsNotice") {
            if BrightIntoshSettings.shared.showIncompatibleAppsNotice {
                self.noticePresenter.resetPresentedApps()
                self.noticePresenter.scheduleIfNeeded()
            }
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleRunningApplicationsDidChange(notification:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleRunningApplicationsDidChange(notification:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        
        noticePresenter.scheduleIfNeeded()
    }
    
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    @objc private func handleRunningApplicationsDidChange(notification: Notification) {
        noticePresenter.scheduleIfNeeded()
    }
}
