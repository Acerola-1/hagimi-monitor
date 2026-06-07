## ADDED Requirements

### Requirement: Entitlements file for sandboxed target
The HagimiMonitor (sandboxed) target SHALL have an entitlements file (`.entitlements`) containing: `com.apple.security.app-sandbox` (true), `com.apple.security.network.client` (true), and `com.apple.security.temporary-exception.mach-lookup.global-name` (array with `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `$(PRODUCT_BUNDLE_IDENTIFIER)-spki`).

#### Scenario: Entitlements file created and configured
- **WHEN** the HagimiMonitor target is built
- **THEN** the build uses the entitlements file with all required entries
- **AND** the app runs with sandbox enabled and network access

#### Scenario: XPC mach-lookup exceptions present
- **WHEN** Sparkle attempts to communicate with its XPC services
- **THEN** the app can connect to both `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` (InstallerLauncher) and `$(PRODUCT_BUNDLE_IDENTIFIER)-spki` (Installer) XPC services

### Requirement: Info.plist Sparkle keys
The HagimiMonitor target's Info.plist SHALL contain: `SUFeedURL` (pointing to the appcast.xml URL), `SUPublicEDKey` (EdDSA public key), and `SUEnableInstallerLauncherService` (true for sandbox support).

#### Scenario: SUFeedURL configured
- **WHEN** Sparkle checks for updates
- **THEN** it fetches the appcast.xml from the URL specified in `SUFeedURL`

#### Scenario: SUEnableInstallerLauncherService enabled
- **WHEN** an update is ready to install on the sandboxed target
- **THEN** Sparkle uses the InstallerLauncher XPC service to perform the installation outside the sandbox

### Requirement: Network client entitlement
The entitlements file SHALL include `com.apple.security.network.client` set to true to allow the app to make outbound network requests for checking updates and downloading app bundles.

#### Scenario: App can reach GitHub for updates
- **WHEN** the app checks for updates or downloads an update
- **THEN** the network request succeeds without sandbox permission errors
