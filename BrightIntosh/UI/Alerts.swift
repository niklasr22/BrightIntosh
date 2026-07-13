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
    let dismissalKey = "dismissedBrightnessFailurePromptForVersion"
    guard BrightIntoshSettings.defaults.string(forKey: dismissalKey) != appVersion else {
        return
    }
    
    SupportReportContext.lastBrightnessFailureReason = reason
    
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = String(localized: "Sorry, BrightIntosh could not reliably increase brightness on this Mac")
    alert.informativeText = String(localized: "Please share anonymous diagnostics so we can look into this brightness issue. The report only includes BrightIntosh data and your running processes, and we'll only use it to investigate this problem.")
    alert.addButton(withTitle: String(localized: "Send Anonymous Diagnostics"))
    alert.addButton(withTitle: String(localized: "Not Now"))
    
    NSApp.activate(ignoringOtherApps: true)
    let response = alert.runModal()
    
    switch response {
    case .alertFirstButtonReturn:
        let report = await generateReport(includeRunningApplications: true)
        BrightIntoshSettings.defaults.set(appVersion, forKey: dismissalKey)
        do {
            try await sendDiagnosticsReport(report)
            showDiagnosticsSentAlert()
        } catch {
            copyDiagnosticsToClipboard(report)
            showDiagnosticsSendFailedAlert()
        }
    case .alertSecondButtonReturn:
        BrightIntoshSettings.defaults.set(appVersion, forKey: dismissalKey)
    default:
        BrightIntoshSettings.defaults.set(appVersion, forKey: dismissalKey)
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
private func showDiagnosticsSentAlert() {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = String(localized: "Diagnostics sent")
    alert.addButton(withTitle: String(localized: "OK"))
    alert.runModal()
}

@MainActor
private func showDiagnosticsSendFailedAlert() {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = String(localized: "Diagnostics could not be sent")
    alert.informativeText = String(localized: "The report was copied to your clipboard instead. Please include it in your support message so the brightness issue can be investigated.")
    alert.addButton(withTitle: String(localized: "OK"))
    alert.runModal()
}
