//
//  HDRCooldownNoticeMonitor.swift
//  BrightIntosh
//
//  Created by Cursor on 26.05.26.
//

import Cocoa

@MainActor
final class HDRCooldownNoticeMonitor {
    private let noticePresenter = HDRCooldownNoticePresenter()
    nonisolated(unsafe) private var hdrCooldownObserver: NSObjectProtocol?
    
    init() {
        hdrCooldownObserver = NotificationCenter.default.addObserver(
            forName: .brightIntoshHDRCooldownDidBegin,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let seconds = notification.userInfo?["cooldownSeconds"] as? Int ?? 30
            let displayID = (notification.userInfo?["displayID"] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
            Task { @MainActor in
                guard !BrightIntoshSettings.shared.ignoreMissingHDRForBrightnessFallback else { return }
                self?.noticePresenter.present(cooldownSeconds: seconds, displayID: displayID, statusItem: nil)
            }
        }
    }
    
    deinit {
        if let hdrCooldownObserver {
            NotificationCenter.default.removeObserver(hdrCooldownObserver)
        }
    }
}
