## ADDED Requirements

### Requirement: Sparkle framework integration
The app SHALL integrate Sparkle 2.x as a Swift Package Manager dependency. The dependency SHALL be added to the Xcode project with the package URL `https://github.com/sparkle-project/Sparkle`.

#### Scenario: Sparkle SPM dependency added
- **WHEN** the Xcode project is opened
- **THEN** Sparkle 2.x appears as a framework dependency for the HagimiMonitor target
- **AND** the project builds successfully with Sparkle imported

### Requirement: UpdaterBridge observable wrapper
The app SHALL provide an `UpdaterBridge` class annotated with `@Observable` and `@MainActor` that wraps `SPUStandardUpdaterController`. It SHALL expose `canCheckForUpdates` as a published property and `checkForUpdates()` as a public method.

#### Scenario: UpdaterBridge initializes Sparkle controller
- **WHEN** UpdaterBridge is initialized
- **THEN** it creates an SPUStandardUpdaterController with `startingUpdater: true`
- **AND** `canCheckForUpdates` reflects the updater's state

#### Scenario: canCheckForUpdates updates reactively
- **WHEN** Sparkle's updater changes its `canCheckForUpdates` state
- **THEN** UpdaterBridge's `canCheckForUpdates` property updates accordingly via KVO observation

### Requirement: SwiftUI environment injection
The app SHALL inject UpdaterBridge into the SwiftUI environment via `@StateObject` in HagimiMonitorApp, making it accessible to all child views through `@Environment`.

#### Scenario: UpdaterBridge available in child views
- **WHEN** a child view declares `@Environment(UpdaterBridge.self) private var updater`
- **THEN** it can access `updater.canCheckForUpdates` and call `updater.checkForUpdates()`

### Requirement: Check for updates in App menu
The app SHALL add a "检查更新…" menu item in the application menu (CommandGroup after appInfo). The menu item SHALL be disabled when `canCheckForUpdates` is false.

#### Scenario: User clicks Check for Updates from menu
- **WHEN** user selects "检查更新…" from the app menu
- **THEN** Sparkle's standard update UI is presented
- **AND** the app checks for updates from the configured feed URL

#### Scenario: Check for Updates disabled during update check
- **WHEN** Sparkle is actively checking for updates
- **THEN** the "检查更新…" menu item is disabled

### Requirement: Check for updates in Settings About pane
The app SHALL add a "检查更新" button in the Settings About pane. The button SHALL use the same UpdaterBridge instance.

#### Scenario: User clicks Check for Updates in Settings
- **WHEN** user clicks "检查更新" in Settings → About
- **THEN** Sparkle's standard update UI is presented

### Requirement: Version display reads from Bundle
The Settings About pane SHALL display the app version by reading `CFBundleShortVersionString` from `Bundle.main.infoDictionary`, replacing the current hardcoded "版本 1.0.0" string.

#### Scenario: Version displays current bundle version
- **WHEN** the Settings About pane is shown
- **THEN** the version text reads the value from `Bundle.main.infoDictionary?["CFBundleShortVersionString"]`
- **AND** displays it as "版本 {version}"

#### Scenario: Version fallback when Bundle info unavailable
- **WHEN** `CFBundleShortVersionString` is nil
- **THEN** the version text displays "版本 未知"
