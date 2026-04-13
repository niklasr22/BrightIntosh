# BrightIntosh — CLAUDE.md

## Project Overview

BrightIntosh is a macOS menu bar utility that enables XDR display brightness (1000 nits) on compatible MacBook Pro (M1 and newer) and external XDR displays at any time. It works by manipulating the display's gamma table and placing a transparent overlay window, bypassing the OS restriction that normally enables the extra brightness range only during HDR playback.

**License:** GNU General Public License v3  
**Language:** Swift  
**Platform:** macOS (minimum target inferred from usage of APIs like `SMAppService`)

---

## Repository Structure

```
BrightIntosh/                   # Main app source
  AppDelegate.swift             # App entry point, keyboard shortcuts, lifecycle
  Authorizer.swift              # Authorization state machine (free vs. Store Edition)
  AutomationManager.swift       # Battery/power adapter/timer automation logic
  BatteryHelpers.swift          # Battery status monitoring via IOKit
  BrightnessManager.swift       # Orchestrates brightness enable/disable/adjust
  BrightnessTechnique.swift     # Base class + GammaTechnique implementation
  BrightIntoshSettings.swift    # Singleton settings backed by UserDefaults (App Group)
  Cli.swift                     # In-process CLI command handler
  cli.sh                        # Shell wrapper that invokes the app with `cli` argument
  Constants.swift               # Supported devices, URLs, keyboard shortcut names
  EntitlementHandler.swift      # StoreKit v2 entitlement verification
  OverlayWindow.swift           # Transparent overlay NSWindow per display
  StoreManager.swift            # StoreKit purchase flow
  Trial.swift                   # Trial period logic (TrialHandler, TrialData)
  Utils.swift                   # IOKit helpers, device detection, report generation
  Products.storekit             # Local StoreKit configuration for testing IAP
  Localizable.xcstrings         # All localized strings (single-file format)
  Assets.xcassets/              # App icons, color sets
  BrightIntosh.entitlements     # Entitlements for the free/direct build
  BrightIntosh_SE.entitlements  # Entitlements for the Mac App Store build
  Info.plist                    # App metadata
  UI/
    Alerts.swift                # NSAlert helpers
    BrightIntoshStore.swift     # Purchase/upgrade UI
    Overlay.swift               # SwiftUI overlay view
    RestorePurchasesButton.swift
    SettingsWindow.swift        # Main settings panel
    StatusBarMenu.swift         # NSStatusItem menu
    StyledSlider.swift          # Custom brightness slider
    Styles.swift                # Reusable SwiftUI styles
    UserStatusModifier.swift    # SwiftUI modifier gating UI on auth status
    WelcomeWindow.swift         # First-launch agreement screen

Shared/
  SharedConstants.swift         # App Group ID, ControlCenter kind, notification names
                                # Shared between main app target and Widgets target

Widgets/
  BrightIntoshControlToggle.swift  # WidgetKit / Control Center toggle widget
  WidgetsBundle.swift              # Widget extension entry point
  Assets.xcassets/
  Info.plist
  Localizable.xcstrings

asc_data/                       # App Store Connect metadata (8 locales)
  {locale}/description.txt
  {locale}/promotional.txt

.github/
  workflows/trigger_website.yml # Triggers website repo rebuild on release
  ISSUE_TEMPLATE/bug_report.md
  ISSUE_TEMPLATE/feature_request.md
  FUNDING.yml

BrightIntosh.xcodeproj/         # Xcode project (do not edit by hand)
```

---

## Two Build Targets / Schemes

| Scheme | Compiler flag | Description |
|--------|---------------|-------------|
| `BrightIntosh` | _(none)_ | Free/direct distribution. `Authorizer` sets status to `.authorizedUnlimited` immediately. |
| `BrightIntosh (Store Editon)` | `-DSTORE` | Mac App Store edition. Runs StoreKit entitlement + trial checks every 5 minutes. |

The `#if STORE` preprocessor guard controls all IAP-related code paths. When `STORE` is not defined, the entire authorization subsystem is bypassed and the app is always fully authorized.

---

## Building

Open `BrightIntosh.xcodeproj` in Xcode and build the desired scheme, **or** use `xcodebuild`:

```bash
# Free edition
xcodebuild -project BrightIntosh.xcodeproj -scheme BrightIntosh build

# Store Edition
xcodebuild -project BrightIntosh.xcodeproj -scheme "BrightIntosh (Store Editon)" build
```

Swift Package Manager resolves automatically (only one dependency: `KeyboardShortcuts` v2.4.0).

There is no shell-script build wrapper; always go through Xcode or `xcodebuild`.

---

## Testing

There are **no automated unit or UI tests** in this project. All verification is manual through the running app.

To run tests via `xcodebuild` (scheme test action exists but is empty):

```bash
xcodebuild -project BrightIntosh.xcodeproj -scheme BrightIntosh test
```

When testing IAP flows, use `Products.storekit` (the StoreKit configuration file) in the Store Edition scheme to simulate purchases locally.

---

## Key Concepts

### Brightness Technique

`BrightnessTechnique` (`BrightnessTechnique.swift`) is an abstract base class. The sole concrete implementation is `GammaTechnique`, which:

1. Creates a `GammaTable` snapshot of the current display calibration.
2. Opens a 1×1 px transparent `OverlayWindow` on each XDR screen (this tricks macOS into allowing the extended brightness range).
3. On every brightness change, multiplies the stored gamma table by the `brightness` factor (range `1.0`–`1.59` or `1.535` depending on device) and calls `CGSetDisplayTransferByTable`.
4. On disable, closes overlay windows and calls `CGDisplayRestoreColorSyncSettings()`.

### Settings

`BrightIntoshSettings` (`BrightIntoshSettings.swift`) is the central `@MainActor` singleton that owns all user preferences:

- Backed by `UserDefaults(suiteName: "group.de.brightintosh.app")` (App Group, shared with the widget).
- Exposes a listener pattern: `addListener(setting:callback:)` — call this to react to a specific setting key changing.
- `cliBrightness` is a separate UserDefaults key observed via KVO so the CLI process can write to it and the running app reacts.

All settings keys use camelCase and match the property names:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `active` | Bool | `true` | Whether BrightIntosh is enabled |
| `brightness` | Float | device max | Gamma multiplier (1.0–max) |
| `cliBrightness` | Float | device max | CLI-controlled brightness (KVO-observed) |
| `brightIntoshOnlyOnBuiltIn` | Bool | `false` | Restrict to built-in display only |
| `hideMenuBarItem` | Bool | `false` | Hide the status bar icon |
| `showInDock` | Bool | `false` | Show app in Dock |
| `batteryAutomation` | Bool | `false` | Auto-disable below battery threshold |
| `batteryAutomationThreshold` | Int | 50 | Battery % threshold |
| `powerAdapterAutomation` | Bool | `false` | Auto-enable when on AC |
| `timerAutomation` | Bool | `false` | Auto-disable after timeout |
| `timerAutomationTimeout` | Int | 180 | Timeout in seconds |

### Authorization (`#if STORE` only)

`Authorizer.shared` publishes an `AuthorizationStatus` enum:

```
unauthorized < pending < authorized < authorizedUnlimited
```

It combines the results of `EntitlementHandler` (StoreKit v2 purchase check) and `TrialHandler` (time-based trial via a remote time server). The highest status wins. A periodic timer re-checks every 5 minutes until `authorizedUnlimited` is reached.

`ValidationCoordinator` serializes concurrent validation calls using a Swift actor.

### CLI

The app handles CLI invocations inline during `applicationDidFinishLaunching`. The binary inspects `CommandLine.arguments`:

```
brightintosh cli <command> [options]
```

Commands: `enable`, `disable`, `toggle`, `set <0-100>`, `status`, `help`

When the first argument is `cli`, `cliBase()` executes the command and calls `exit(0)`. This means the app starts, runs the CLI action via `BrightIntoshSettings`, and quits immediately — it does **not** show any UI. The CLI requires the main app to be running so it can communicate via shared `UserDefaults`.

### Supported Devices

Defined in `Constants.swift`:

- **Built-in XDR support:** `MacBookPro18,x` (M1 Pro/Max 14/16-inch) through `Mac17,x` (M5-series).
- **External XDR displays:** `"Pro Display XDR"`, `"Studio Display XDR"` (and `"C34H89x"` in DEBUG builds only).
- **Device max brightness multiplier:**
  - `1.535` — M3/M4/M5 devices (`Mac15,x`, `Mac16,x`, `Mac17,x`)
  - `1.59` — all other supported devices

Adding a new device requires updating `supportedDevices` and potentially `sdr600nitsDevices` in `Constants.swift`, and bumping the version.

---

## Architecture Patterns

- **`@MainActor` everywhere** — all UI and settings mutations happen on the main actor. Use `Task { @MainActor in ... }` when bridging from non-isolated contexts.
- **Singleton pattern** — `BrightIntoshSettings.shared`, `Authorizer.shared`, `EntitlementHandler.shared`, `ValidationCoordinator.shared`.
- **Listener/observer pattern** — `BrightIntoshSettings.addListener(setting:callback:)` is used throughout instead of Combine or NotificationCenter for settings changes.
- **Combine** — used in `BrightnessManager` and `Authorizer` for cross-singleton state propagation (`$status` publisher).
- **SwiftUI + AppKit hybrid** — the app entry point is `@main struct AppWithMenuBarExtra: App` (SwiftUI lifecycle) with an `NSApplicationDelegateAdaptor`. Windows are driven by `NSWindowController` subclasses containing SwiftUI views via `NSHostingView`.
- **App Group UserDefaults** — suite name `group.de.brightintosh.app` shared between the main app and the Widgets extension.

---

## Code Conventions

- **File header:** `// Created by Niklas Rousset on <date>.` — maintain this style for new files.
- **Scope:** Default to `private`; use `public` only where required by protocol conformance or cross-module access.
- **Async/await:** Prefer `async/await` over callbacks. Bridge legacy callbacks with `withCheckedContinuation`.
- **`@MainActor` functions:** Mark free functions that touch UI or settings with `@MainActor`.
- **No force-unwraps** except where the value is guaranteed by the bundle (e.g., `appVersion`).
- **Localization:** All user-facing strings must go through `NSLocalizedString` or Swift string interpolation with `String(localized:)`. Strings live in `BrightIntosh/Localizable.xcstrings`.
- **No new test files** — the project has no test infrastructure; do not create test targets without discussing it first.

---

## CI/CD

GitHub Actions (`.github/workflows/trigger_website.yml`):

- Triggers on `release` events (published or edited).
- Dispatches a `rebuild` event to the `niklasr22/brightintosh-website` repository via `peter-evans/repository-dispatch`.
- Requires the `WEBSITE_REPO_PAT` secret.

There is no automated build or test workflow. Releases are created manually.

---

## Known Incompatibilities

- **f.lux** — likely incompatible; both apps manipulate gamma tables.
- **HDR video** — will clip when BrightIntosh is active because the gamma table offset lifts the entire range.

---

## Development Tips

- To test the Store Edition IAP flow locally, select the `BrightIntosh (Store Editon)` scheme and ensure `Products.storekit` is set as the StoreKit Configuration in the scheme's Run options.
- The `generateReport()` function in `Utils.swift` produces a diagnostic report useful for bug reproduction; it is surfaced via the bug report issue template.
- Screen wake is handled in `BrightnessManager.screensWake(notification:)` to re-apply gamma after sleep/wake cycles.
- When adding a new automation type, follow the pattern in `AutomationManager.swift`: listen to the relevant setting key via `BrightIntoshSettings.shared.addListener` and update `brightintoshActive` accordingly.
