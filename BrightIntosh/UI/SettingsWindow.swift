//
//  SettingsWindow.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 17.09.23.
//

import KeyboardShortcuts
import OSLog
import SwiftUI

@MainActor
class BasicSettingsViewModel: ObservableObject {
    /*
     This View Model is used for settings that can be changed via shortcuts or another way other than the settings UI, so changes can be obeserved and showed in the UI.
     */
    private var brightIntoshActive = BrightIntoshSettings.shared.brightintoshActive
    var brightIntoshActiveToggle: Bool {
        set { BrightIntoshSettings.shared.brightintoshActive = newValue }
        get { return brightIntoshActive }
    }
    private var batteryAutomation = BrightIntoshSettings.shared.batteryAutomation
    var batteryAutomationToggle: Bool {
        set { BrightIntoshSettings.shared.batteryAutomation = newValue }
        get { return batteryAutomation }
    }

    private var timerAutomation = BrightIntoshSettings.shared.timerAutomation
    var timerAutomationToggle: Bool {
        set { BrightIntoshSettings.shared.timerAutomation = newValue }
        get { return timerAutomation }
    }
    
    private var timerAutomationTimeoutValue = BrightIntoshSettings.shared.timerAutomationTimeout
    var timerAutomationTimeout: Int {
        set {
            BrightIntoshSettings.shared.timerAutomation = newValue > 0
            BrightIntoshSettings.shared.timerAutomationTimeout = newValue
        }
        get { return timerAutomationToggle ? timerAutomationTimeoutValue : 0 }
    }
    
    private var powerAdapterAutomation = BrightIntoshSettings.shared.powerAdapterAutomation
    var powerAdapterAutomationToggle: Bool {
        set { BrightIntoshSettings.shared.powerAdapterAutomation = newValue }
        get { return powerAdapterAutomation }
    }

    init() {
        BrightIntoshSettings.shared.addListener(setting: "brightintoshActive") {
            if BrightIntoshSettings.shared.brightintoshActive && !checkBatteryAutomationContradiction() {
                BrightIntoshSettings.shared.brightintoshActive = false
            }
            if self.brightIntoshActive != BrightIntoshSettings.shared.brightintoshActive {
                self.brightIntoshActive = BrightIntoshSettings.shared.brightintoshActive
                self.objectWillChange.send()
            }
        }
        BrightIntoshSettings.shared.addListener(setting: "batteryAutomation") {
            if self.batteryAutomation != BrightIntoshSettings.shared.batteryAutomation {
                self.batteryAutomation = BrightIntoshSettings.shared.batteryAutomation
                self.objectWillChange.send()
            }
        }
        BrightIntoshSettings.shared.addListener(setting: "timerAutomation") {
            if self.timerAutomation != BrightIntoshSettings.shared.timerAutomation {
                self.timerAutomation = BrightIntoshSettings.shared.timerAutomation
                self.objectWillChange.send()
            }
        }
        BrightIntoshSettings.shared.addListener(setting: "timerAutomationTimeout") {
            if self.timerAutomationTimeoutValue != BrightIntoshSettings.shared.timerAutomationTimeout {
                self.timerAutomationTimeoutValue = BrightIntoshSettings.shared.timerAutomationTimeout
                self.objectWillChange.send()
            }
        }
        BrightIntoshSettings.shared.addListener(setting: "powerAdapterAutomation") {
            if self.powerAdapterAutomation != BrightIntoshSettings.shared.powerAdapterAutomation {
                self.powerAdapterAutomation = BrightIntoshSettings.shared.powerAdapterAutomation
                self.objectWillChange.send()
            }
        }
    }
}

struct BrightnessSliderRemovalHint: View {
    @Binding var isVisible: Bool

    var body: some View {
        if isVisible {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text("The BrightIntosh brightness slider was removed. Use your Mac's normal brightness keys to adjust brightness, and simply toggle increased brightness on or off when you need the boost.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Dismiss") {
                    BrightIntoshSettings.shared.dismissedBrightnessSliderRemovalHint = true
                    isVisible = false
                }
                .buttonStyle(.borderless)
            }
            .padding(10)
            .background(Color.blue.opacity(0.12))
            .clipShape(.rect(cornerRadius: 8))
        }
    }
}

struct CliInstallationSheet: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Install the BrightIntosh CLI")
                .font(.title)
            HStack {
                Text(getCliInstallCommand())
                    .textSelection(.enabled)
                    .font(.caption)
                    .monospaced()
                Button(action: copyToClipboard) {
                    Image(systemName: "document.on.document")
                }
            }
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(Color.black)
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: 15.0))
            Text("Help")
                .font(.title2)
            Text(getHelpText())
                .monospaced()
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.black)
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: 15.0))
            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight:    .infinity)
            .padding()
            .navigationBarBackButtonHidden(false)
    }
    
    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(getCliInstallCommand(), forType: .string)
    }
    
    func getCliInstallCommand() -> String {
        let bundlePath = Bundle.main.bundlePath
        return "echo \"alias brightintosh='\(bundlePath)/Contents/Resources/cli.sh'\" >> ~/.zshrc && source ~/.zshrc"
    }
}

struct SupportReportSheet: View {
    @Binding var isPresented: Bool
    @State private var includeRunningApplications = true
    @State private var report = ""
    @State private var isGenerating = false
    @State private var didCopy = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Support report")
                .font(.title2)
                .bold()
            
            Text("Review the report before sharing it. It includes device, display, and BrightIntosh diagnostics.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Toggle("Include running applications", isOn: $includeRunningApplications)
                .onChange(of: includeRunningApplications) { _, _ in
                    Task { await regenerateReport() }
                }
            
            Group {
                if isGenerating {
                    ProgressView("Generating report…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(report)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.85))
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 12))
                }
            }
            .frame(minHeight: 280, maxHeight: .infinity)
            
            HStack {
                if didCopy {
                    Text("Copied to clipboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Copy to clipboard") {
                    copyReport()
                }
                .disabled(report.isEmpty || isGenerating)
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520, height: 480)
        .task {
            await regenerateReport()
        }
    }
    
    private func regenerateReport() async {
        isGenerating = true
        didCopy = false
        report = await generateReport(includeRunningApplications: includeRunningApplications)
        isGenerating = false
    }
    
    private func copyReport() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
        didCopy = true
    }
}

struct AdvancedSettingsSheet: View {
    @Binding var isPresented: Bool
    @Binding var useAlternateBrightnessBackend: Bool
    @Binding var waitForHDRBeforeIncreasingBrightness: Bool
    @Binding var useCompatibilityBrightnessMode: Bool
    @State private var didChangeCompatibilityBrightnessMode = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Advanced")
                .font(.title2)
                .bold()
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle(
                    "Compatibility Mode",
                    isOn: $useCompatibilityBrightnessMode
                )
                .onChange(of: useCompatibilityBrightnessMode) { _, new in
                    BrightIntoshSettings.shared.useCompatibilityBrightnessMode = new
                    didChangeCompatibilityBrightnessMode = true
                }
                
                Text("Uses an older, simpler brightness method. It may work better on some Macs, but can be less color-accurate. Restart BrightIntosh to apply this change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if didChangeCompatibilityBrightnessMode {
                    Label(
                        "Restart BrightIntosh to switch brightness modes.",
                        systemImage: "arrow.clockwise.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                
                Toggle(
                    "Use alternate brightness backend",
                    isOn: $useAlternateBrightnessBackend
                )
                .onChange(of: useAlternateBrightnessBackend) { _, new in
                    BrightIntoshSettings.shared.useAlternateBrightnessBackend = new
                }
                .disabled(useCompatibilityBrightnessMode)
                
                if useCompatibilityBrightnessMode {
                    Text("The alternate brightness backend only applies to Standard Mode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Toggle(
                    "Wait for HDR before increasing brightness",
                    isOn: $waitForHDRBeforeIncreasingBrightness
                )
                .onChange(of: waitForHDRBeforeIncreasingBrightness) { _, new in
                    BrightIntoshSettings.shared.waitForHDRBeforeIncreasingBrightness = new
                }
                
                Text("These options can help when extra brightness does not behave as expected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 420)
    }
}

struct BasicSettings: View {
    @ObservedObject var viewModel = BasicSettingsViewModel()
    
    @State private var showInDock = BrightIntoshSettings.shared.showInDock
    @State private var hideMenuBarItem = BrightIntoshSettings.shared.hideMenuBarItem
    @State private var launchOnLogin = BrightIntoshSettings.shared.launchAtLogin
    @State private var brightIntoshOnlyOnBuiltIn = BrightIntoshSettings.shared.brightIntoshOnlyOnBuiltIn
    @State private var disableWhenLidClosed = BrightIntoshSettings.shared.disableWhenLidClosed
    @State private var showHDRRetryCooldownNotice = BrightIntoshSettings.shared.showHDRRetryCooldownNotice
    @State private var showIncompatibleAppsNotice = BrightIntoshSettings.shared.showIncompatibleAppsNotice
    @State private var useAlternateBrightnessBackend = BrightIntoshSettings.shared.useAlternateBrightnessBackend
    @State private var waitForHDRBeforeIncreasingBrightness = BrightIntoshSettings.shared.waitForHDRBeforeIncreasingBrightness
    @State private var useCompatibilityBrightnessMode = BrightIntoshSettings.shared.useCompatibilityBrightnessMode
    @State private var batteryLevelThreshold = BrightIntoshSettings.shared.batteryAutomationThreshold
    @State private var timerAutomationTimeout = BrightIntoshSettings.shared.timerAutomationTimeout

    @State private var entitledToUnrestrictedUse = false
    @Environment(\.isUnrestrictedUser) private var isUnrestrictedUser: Bool
    
    @State private var showCliPopup = false
    @State private var showSupportReportSheet = false
    @State private var showBrightnessSliderRemovalHint = false
    @State private var showAdvancedSettingsSheet = false

    var body: some View {
        ScrollView {
            Form {
                Section(header: Text("Brightness").bold()) {
                    BrightnessSliderRemovalHint(isVisible: $showBrightnessSliderRemovalHint)
                    Toggle("Increased brightness", isOn: $viewModel.brightIntoshActiveToggle)
                    if isDeviceSupported() {
                        Toggle(
                            "Don't apply increased brightness to external XDR displays",
                            isOn: $brightIntoshOnlyOnBuiltIn
                        )
                        .onChange(of: brightIntoshOnlyOnBuiltIn) { _, new in
                            BrightIntoshSettings.shared.brightIntoshOnlyOnBuiltIn = new
                        }
                    } else {
                        Label(
                            "Your device doesn't have a built-in XDR display. Increased brightness can only be enabled for external XDR displays.",
                            systemImage: "exclamationmark.triangle.fill"
                        ).foregroundColor(Color.yellow)
                    }
                    Toggle(
                        "Show a notice when boosted brightness needs a short delay",
                        isOn: $showHDRRetryCooldownNotice
                    )
                    .onChange(of: showHDRRetryCooldownNotice) { _, new in
                        BrightIntoshSettings.shared.showHDRRetryCooldownNotice = new
                    }
                    Toggle(
                        "Show a notice when another brightness app may interfere",
                        isOn: $showIncompatibleAppsNotice
                    )
                    .onChange(of: showIncompatibleAppsNotice) { _, new in
                        BrightIntoshSettings.shared.showIncompatibleAppsNotice = new
                    }
                }
                Section(header: Text("Timer").bold()) {
                    Picker(selection: $viewModel.timerAutomationTimeout, label: Text("Disable after")) {
                        Text("Never").tag(0)
                        ForEach(Array(stride(from: 10, to: 51, by: 10)), id: \.self) {
                            minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                        ForEach(Array(stride(from: 1, to: 5, by: 0.5)), id: \.self) { hours in
                            Text(String(format: "%.1f h", hours)).tag(Int(hours * 60))
                        }
                    }
                    .onChange(of: timerAutomationTimeout) { _, new in
                        viewModel.timerAutomationTimeout = new
                    }
                }
                Section(header: Text("Automations").bold()) {
                    Toggle("Launch on login", isOn: $launchOnLogin)
                        .onChange(of: launchOnLogin) { _, new in
                            BrightIntoshSettings.shared.launchAtLogin = new
                        }
                    Toggle("Disable when the MacBook lid is closed", isOn: $disableWhenLidClosed)
                        .onChange(of: disableWhenLidClosed) { _, new in
                            BrightIntoshSettings.shared.disableWhenLidClosed = new
                        }
                    Picker(selection: $batteryLevelThreshold, label: Text("Disable when battery level drops under")) {
                        Text("Never").tag(100)
                        ForEach(Array(stride(from: 5, to: 100, by: 5)), id: \.self) {
                            percent in
                            Text("\(percent) %").tag(percent)
                        }
                    }
                    .onChange(of: batteryLevelThreshold) { _, new in
                        BrightIntoshSettings.shared.batteryAutomation = batteryLevelThreshold != 100
                        BrightIntoshSettings.shared.batteryAutomationThreshold = new
                    }
                    Toggle(
                        "Disable when on battery, enable when plugged in",
                        isOn: $viewModel.powerAdapterAutomationToggle)
                }
                Section(header: Text("Shortcuts").bold()) {
                    KeyboardShortcuts.Recorder(
                        "Toggle increased brightness:", name: .toggleBrightIntosh)
                    KeyboardShortcuts.Recorder(
                        "Open settings:", name: .openSettings)
                }
                Section(
                    header: Text("General").bold(),
                    footer: HStack {
                        Spacer()
                        Button("Advanced...") {
                            showAdvancedSettingsSheet = true
                        }
                        .sheet(isPresented: $showAdvancedSettingsSheet) {
                            AdvancedSettingsSheet(
                                isPresented: $showAdvancedSettingsSheet,
                                useAlternateBrightnessBackend: $useAlternateBrightnessBackend,
                                waitForHDRBeforeIncreasingBrightness: $waitForHDRBeforeIncreasingBrightness,
                                useCompatibilityBrightnessMode: $useCompatibilityBrightnessMode
                            )
                        }
                    },
                    content: {
                        Toggle(
                            "Hide menu bar item",
                            isOn: $hideMenuBarItem)
                        .onChange(of: hideMenuBarItem) { _, new in
                            BrightIntoshSettings.shared.hideMenuBarItem = new
                        }
                        if hideMenuBarItem {
                            Label(
                                "To open the settings window without the menu bar item, search for \"BrightIntosh Settings\" in the the macOS \(Image(systemName: "magnifyingglass")) Spotlight search.",
                                systemImage: "exclamationmark.triangle.fill"
                            ).foregroundColor(Color.yellow)
                        }
                        Toggle(
                            "Show in dock",
                            isOn: $showInDock)
                        .onChange(of: showInDock) { _, new in
                            BrightIntoshSettings.shared.showInDock = new
                        }
                        Button(action: {
                            showSupportReportSheet = true
                        }) {
                            Text("Generate report…")
                        }
                        Button(action: {
                            showCliPopup = true
                        }) {
                            Text("Install BrightIntosh CLI")
                        }
                    })
#if DEBUG
                Section(header: Text("Dev").bold()) {
                    Button("Reset brightness slider hint dismissal") {
                        BrightIntoshSettings.shared.dismissedBrightnessSliderRemovalHint = false
                        Task {
                            await updateBrightnessSliderRemovalHintVisibility()
                        }
                    }
                    Button("Show brightness failure prompt") {
                        BrightIntoshSettings.defaults.removeObject(forKey: "dismissedBrightnessFailurePromptForVersion")
                        Task {
                            await presentBrightnessFailurePrompt(reason: "Manually triggered from Debug settings.")
                        }
                    }
                }
                .background(.clear)
#endif
            }
        }
        .formStyle(.grouped)
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: 0,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .sheet(isPresented: $showCliPopup) {
            CliInstallationSheet(isPresented: $showCliPopup)
        }
        .sheet(isPresented: $showSupportReportSheet) {
            SupportReportSheet(isPresented: $showSupportReportSheet)
        }
        .task {
            await updateBrightnessSliderRemovalHintVisibility()
        }
    }

    @MainActor
    private func updateBrightnessSliderRemovalHintVisibility() async {
        guard !BrightIntoshSettings.shared.dismissedBrightnessSliderRemovalHint else {
            showBrightnessSliderRemovalHint = false
            return
        }

        showBrightnessSliderRemovalHint = await originalPurchaseVersionIsEarlierThan(brightnessSliderRemovalOriginalPurchaseVersionCutoff)
    }
}

struct Acknowledgments: View {
    var body: some View {
        VStack(alignment: HorizontalAlignment.leading) {
            ScrollView {
                ForEach(acknowledgments) { ack in
                    Text(ack.title).font(.title2)
                    Text(ack.text)
                }
            }
        }.frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: 0,
            maxHeight: .infinity,
            alignment: .topLeading
        ).padding()
    }
}

struct VersionView: View {
    #if STORE
        var title: String = "BrightIntosh SE v\(appVersion)"
        @Environment(\.isUnrestrictedUser) private var isUnrestrictedUser: Bool
    #else
        var title: String = "BrightIntosh v\(appVersion)"
        private let isUnrestrictedUser: Bool = true
    #endif

    @State var clicks = 0

    @State var ignoreAppTransaction = BrightIntoshSettings.shared.ignoreAppTransaction

    var body: some View {
        VStack {
            Label(title + (isUnrestrictedUser ? "" : " - Free Trial"), image: "LogoBordered")
                .imageScale(.small)
                .onTapGesture {
                    clicks += 1
                }
            HStack {
                Button(
                    action: {
                        NSWorkspace.shared.open(BrightIntoshUrls.help)
                    },
                    label: {
                        Image(systemName: "questionmark.circle")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .padding(4.0)
                    }
                )
                .help("Help")
                Button(action: {
                    NSWorkspace.shared.open(BrightIntoshUrls.twitter)
                }) {
                    Image("X")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .padding(4.0)
                }
                .help("X / Twitter")
            }
        }
        #if STORE
            if clicks >= 5 {
                VStack {
                    Text("Test Settings").font(.title2)
                    Toggle(isOn: $ignoreAppTransaction) {
                        Text("Test: Ignore App Transaction")
                    }
                    .onChange(of: ignoreAppTransaction) {
                        BrightIntoshSettings.shared.ignoreAppTransaction = ignoreAppTransaction
                        Task {
                            _ = try? await EntitlementHandler.shared.isUnrestrictedUser()
                        }
                    }
                    Button("Hide") {
                        clicks = 0
                    }
                }
            }
        #endif
    }
}

struct SettingsTabs: View {
    @Environment(\.isUnrestrictedUser) private var isUnrestrictedUser: Bool

    var body: some View {
        TabView {
            #if STORE
                if !isUnrestrictedUser {
                    BrightIntoshStoreView(showTrialExpiredWarning: true).tabItem {
                        Text("Store")
                    }
                }
            #endif
            BasicSettings().tabItem {
                Text("General")
            }
            Acknowledgments().tabItem {
                Text("Acknowledgments")
            }
        }
    }
}

struct SettingsView: View {
    var body: some View {
        VStack {
            if #unavailable(macOS 15) {
                Text("Settings").font(.largeTitle)
            }
            SettingsTabs()
            VersionView()
        }
        .padding()
        .userStatusTask()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .frame(width: 650, height: 590)
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init() {

        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 590),
            styleMask: [.titled, .closable, .unifiedTitleAndToolbar],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "BrightIntosh Settings"

        let contentView = SettingsView().frame(width: 650, height: 590)

        settingsWindow.contentView = NSHostingView(rootView: contentView)
        settingsWindow.center()

        super.init(window: settingsWindow)
        settingsWindow.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        window?.level = .floating
        super.showWindow(sender)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.stopModal()
    }
}
