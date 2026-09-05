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
private final class ForegroundAlertPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class ForegroundAlertSession: NSObject, NSWindowDelegate {
    private let panel: ForegroundAlertPanel
    private var continuation: CheckedContinuation<NSApplication.ModalResponse, Never>?
    private var didFinish = false

    init(
        style: NSAlert.Style,
        title: String,
        message: String?,
        buttonTitles: [String]
    ) {
        panel = ForegroundAlertPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel(
            style: style,
            title: title,
            message: message,
            buttonTitles: buttonTitles
        )
    }

    func response() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            self.continuation = continuation

            panel.delegate = self
            panel.level = .modalPanel
            panel.center()
            NSApp.activate(ignoringOtherApps: true)
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    private func configurePanel(
        style: NSAlert.Style,
        title: String,
        message: String?,
        buttonTitles: [String]
    ) {
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = false
        panel.titlebarSeparatorStyle = .none
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = true
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true

        let contentView = NSView()
        panel.contentView = contentView

        let informational = style == .informational
        let iconImage = NSImage(
            systemSymbolName: informational
                ? "checkmark.circle.fill"
                : "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        )
        let icon = NSImageView(image: iconImage ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 27,
            weight: .medium
        )
        icon.contentTintColor = informational ? .systemGreen : .systemOrange

        let titleLabel = NSTextField(wrappingLabelWithString: title)
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .labelColor

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 6
        textStack.addArrangedSubview(titleLabel)

        if let message, !message.isEmpty {
            let messageLabel = NSTextField(wrappingLabelWithString: message)
            messageLabel.font = .systemFont(ofSize: 12.5)
            messageLabel.textColor = .secondaryLabelColor
            textStack.addArrangedSubview(messageLabel)
        }

        let messageRow = NSStackView(views: [icon, textStack])
        messageRow.orientation = .horizontal
        messageRow.alignment = .top
        messageRow.spacing = 14

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        for index in buttonTitles.indices.reversed() {
            let localizedTitle = buttonTitles[index]
            let button = NSButton(
                title: localizedTitle.isEmpty ? String(localized: "OK") : localizedTitle,
                target: self,
                action: #selector(buttonPressed(_:))
            )
            button.tag = index
            button.bezelStyle = .rounded
            button.controlSize = .large
            if index == 0 {
                button.keyEquivalent = "\r"
            } else if index == 1 {
                button.keyEquivalent = "\u{1b}"
            }
            buttonRow.addArrangedSubview(button)
        }

        let rootStack = NSStackView(views: [messageRow, buttonRow])
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.orientation = .vertical
        rootStack.alignment = .trailing
        rootStack.spacing = 18
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 36),
            icon.heightAnchor.constraint(equalToConstant: 36),
            textStack.widthAnchor.constraint(equalToConstant: 336),
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
        ])

        contentView.layoutSubtreeIfNeeded()
        let contentHeight = max(154, rootStack.fittingSize.height + 36)
        panel.setContentSize(NSSize(width: 430, height: contentHeight))
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        let response = NSApplication.ModalResponse(
            rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + sender.tag
        )
        finish(response: response)
    }

    func windowWillClose(_ notification: Notification) {
        finish(response: .abort, closePanel: false)
    }

    private func finish(
        response: NSApplication.ModalResponse,
        closePanel: Bool = true
    ) {
        guard !didFinish else { return }
        didFinish = true
        panel.delegate = nil
        panel.orderOut(nil)
        if closePanel {
            panel.close()
        }
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: response)
    }
}

@MainActor
private func presentForegroundAlert(
    style: NSAlert.Style,
    title: String,
    message: String? = nil,
    buttonTitles: [String]
) async -> NSApplication.ModalResponse {
    await ForegroundAlertSession(
        style: style,
        title: title,
        message: message,
        buttonTitles: buttonTitles
    ).response()
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
private final class BrightnessFailurePromptCoordinator {
    static let shared = BrightnessFailurePromptCoordinator()

    private let promptVersionKey = "brightnessFailurePromptVersion"
    private let promptDateKey = "brightnessFailurePromptDate"
    private var isPresenting = false
    private var activeReasons: [String] = []

    func present(reason: String) async {
        if isPresenting {
            appendActiveReason(reason)
            BrightnessDiagnosticHistory.record(
                "Coalesced duplicate brightness failure prompt while one was already active: \(reason)"
            )
            return
        }

        let defaults = BrightIntoshSettings.defaults
        let lastPromptDate = defaults.object(forKey: promptDateKey) as? Date ?? .distantPast
        guard defaults.string(forKey: promptVersionKey) != appVersion,
              Date().timeIntervalSince(lastPromptDate) >= 7 * 24 * 60 * 60 else {
            SupportReportContext.lastBrightnessFailureReason = reason
            BrightnessDiagnosticHistory.record(
                "Brightness failure prompt suppressed by version/weekly limit: \(reason)"
            )
            return
        }

        // Reserve before presenting: declining, restarting, or a failed send must not prompt again.
        defaults.set(appVersion, forKey: promptVersionKey)
        defaults.set(Date(), forKey: promptDateKey)
        isPresenting = true
        activeReasons = []
        appendActiveReason(reason)
        defer {
            isPresenting = false
            activeReasons = []
        }

        let response = await presentForegroundAlert(
            style: .warning,
            title: String(localized: "Sorry, BrightIntosh could not reliably increase brightness on this Mac"),
            message: String(localized: "Please share anonymous diagnostics so we can look into this brightness issue. The report only includes BrightIntosh data and your running processes, and we'll only use it to investigate this problem."),
            buttonTitles: [
                String(localized: "Send Anonymous Diagnostics"),
                String(localized: "Not Now"),
            ]
        )

        guard response == .alertFirstButtonReturn else { return }
        updateSupportReportReason()
        let report = await generateReport(includeRunningApplications: true)
        do {
            try await sendDiagnosticsReport(report)
        } catch {
            copyDiagnosticsToClipboard(report)
            await showDiagnosticsSendFailedAlert()
        }
    }

    private func appendActiveReason(_ reason: String) {
        if !activeReasons.contains(reason) {
            activeReasons.append(reason)
        }
        updateSupportReportReason()
    }

    private func updateSupportReportReason() {
        SupportReportContext.lastBrightnessFailureReason = activeReasons.joined(
            separator: " | "
        )
    }
}

@MainActor
func presentBrightnessFailurePrompt(reason: String) async {
    await BrightnessFailurePromptCoordinator.shared.present(reason: reason)
}

@MainActor
func scheduleBrightnessFailurePrompt(reason: String, while isStillFailing: @escaping @MainActor () -> Bool) {
    Task { @MainActor in
        // Brief outages and failures resolved by a user action should never interrupt the user.
        for _ in 0..<60 {
            guard isStillFailing() else { return }
            try? await Task.sleep(for: .seconds(2))
        }
        guard isStillFailing() else { return }
        await presentBrightnessFailurePrompt(reason: reason)
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
private func showDiagnosticsSendFailedAlert() async {
    _ = await presentForegroundAlert(
        style: .warning,
        title: String(localized: "Diagnostics could not be sent"),
        message: String(localized: "The report was copied to your clipboard instead. Please include it in your support message so the brightness issue can be investigated."),
        buttonTitles: [String(localized: "OK")]
    )
}
