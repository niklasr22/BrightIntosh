//
//  Alerts.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 02.10.23.
//

import Foundation
import Cocoa

private enum DiagnosticsSendError: Error {
    case invalidResponse
    case rejected(Int)
}

@MainActor
private final class ModelessAlertSession: NSObject, NSWindowDelegate {
    private let alert: NSAlert
    private var continuation: CheckedContinuation<NSApplication.ModalResponse, Never>?
    private var didFinish = false

    init(alert: NSAlert) {
        self.alert = alert
    }

    func response() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            self.continuation = continuation

            let window = alert.window
            for (index, button) in alert.buttons.enumerated() {
                button.tag = index
                button.target = self
                button.action = #selector(buttonPressed(_:))
            }

            window.delegate = self
            window.isReleasedWhenClosed = false
            window.level = .modalPanel
            window.center()
            NSApp.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
            window.makeKey()
        }
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        let response = NSApplication.ModalResponse(
            rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + sender.tag
        )
        finish(response: response)
    }

    func windowWillClose(_ notification: Notification) {
        finish(response: .abort)
    }

    private func finish(response: NSApplication.ModalResponse) {
        guard !didFinish else { return }
        didFinish = true
        alert.window.delegate = nil
        alert.window.orderOut(nil)
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: response)
    }
}

@MainActor
private func presentModelessAlert(_ alert: NSAlert) async -> NSApplication.ModalResponse {
    alert.showsSuppressionButton = false

    if let parentWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: {
        $0.isVisible && $0.canBecomeKey && !($0 is NSPanel)
    }) {
        NSApp.activate(ignoringOtherApps: true)
        parentWindow.makeKeyAndOrderFront(nil)
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: parentWindow) { response in
                continuation.resume(returning: response)
            }
        }
    }

    return await ModelessAlertSession(alert: alert).response()
}

@MainActor func createBatteryAutomationContradictionAlert() -> NSAlert {
    let alert = NSAlert()
    alert.messageText = String(
        format: String(localized: "Your battery level is below %d%%. Do you want to activate increased brightness anyway?\n\nThis will disable the battery automation."),
        BrightIntoshSettings.shared.batteryAutomationThreshold
    )
    alert.addButton(withTitle: String(localized: "Continue"))
    alert.addButton(withTitle: String(localized: "Cancel"))
    return alert
}

@MainActor
func presentBrightnessFailurePrompt(reason: String) async {
    SupportReportContext.lastBrightnessFailureReason = reason
    
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = String(localized: "Sorry, BrightIntosh could not reliably increase brightness on this Mac")
    alert.informativeText = String(localized: "Please share anonymous diagnostics so we can look into this brightness issue. The report only includes BrightIntosh data and your running processes, and we'll only use it to investigate this problem.")
    alert.addButton(withTitle: String(localized: "Send Anonymous Diagnostics"))
    alert.addButton(withTitle: String(localized: "Not Now"))
    
    let response = await presentModelessAlert(alert)

    guard response == .alertFirstButtonReturn else { return }
    let report = await generateReport(includeRunningApplications: true)
    do {
        try await sendDiagnosticsReport(report)
        await showDiagnosticsSentAlert()
    } catch {
        copyDiagnosticsToClipboard(report)
        await showDiagnosticsSendFailedAlert()
    }
}

@MainActor
private func sendDiagnosticsReport(_ report: String) async throws {
    var request = URLRequest(url: BrightIntoshUrls.report)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
    
    var components = URLComponents()
    components.queryItems = [
        URLQueryItem(name: "app_version", value: appVersion),
        URLQueryItem(name: "model_identifier", value: getModelIdentifier() ?? "N/A"),
        URLQueryItem(name: "os_version", value: ProcessInfo.processInfo.operatingSystemVersionString),
        URLQueryItem(name: "report", value: report),
    ]
    request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
    
    let (_, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
        throw DiagnosticsSendError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
        throw DiagnosticsSendError.rejected(httpResponse.statusCode)
    }
}

@MainActor
private func copyDiagnosticsToClipboard(_ report: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(report, forType: .string)
}

@MainActor
private func showDiagnosticsSentAlert() async {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = String(localized: "Diagnostics sent")
    alert.addButton(withTitle: String(localized: "OK"))
    _ = await presentModelessAlert(alert)
}

@MainActor
private func showDiagnosticsSendFailedAlert() async {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = String(localized: "Diagnostics could not be sent")
    alert.informativeText = String(localized: "The report was copied to your clipboard instead. Please include it in your support message so the brightness issue can be investigated.")
    alert.addButton(withTitle: String(localized: "OK"))
    _ = await presentModelessAlert(alert)
}
