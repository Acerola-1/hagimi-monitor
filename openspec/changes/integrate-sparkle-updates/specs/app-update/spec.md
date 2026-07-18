## ADDED Requirements

### Requirement: Channel-Split Update Behavior
The application SHALL determine its update behavior by distribution channel via the `DIRECT_DISTRIBUTION` compilation condition. App Store builds SHALL contain no in-app update path; direct-distribution builds SHALL provide in-app updates.

#### Scenario: App Store build has no update entry
- **WHEN** the App Store build (no `DIRECT_DISTRIBUTION`) is running
- **THEN** the About page shows no "check for updates" entry
- **AND** the app performs no update-check network requests
- **AND** the built product neither links nor embeds Sparkle

#### Scenario: Direct build provides in-app updates
- **WHEN** the direct-distribution build is running
- **THEN** the About page shows a "check for updates" action backed by Sparkle

### Requirement: Sparkle Auto-Update For Direct Builds
Direct-distribution builds SHALL use Sparkle to check, download, verify, and install updates in-app, started at launch for background checks.

#### Scenario: User checks for updates
- **WHEN** the user taps "Check for Updates" in the direct build
- **THEN** Sparkle checks the appcast feed
- **AND** if a newer version exists, Sparkle presents a release-notes dialog and can download, verify (EdDSA), install, and relaunch without leaving the app

#### Scenario: Background check at launch
- **WHEN** the direct build launches
- **THEN** the Sparkle updater is started and performs its scheduled background checks

#### Scenario: Update integrity is verified
- **WHEN** Sparkle downloads an update
- **THEN** it verifies the update against the embedded EdDSA public key before installing

### Requirement: GitHub Download Fallback
The direct build SHALL always show a fallback entry to download from GitHub in a browser, so users who cannot complete the in-app download can still update manually.

#### Scenario: Fallback always visible
- **WHEN** the About page is shown in the direct build
- **THEN** a "Download from GitHub" link is visible regardless of Sparkle state

#### Scenario: Fallback opens releases page
- **WHEN** the user activates the "Download from GitHub" link
- **THEN** the GitHub Releases page opens in the default browser

### Requirement: Appcast Publication
The release pipeline SHALL publish a Sparkle appcast and a signed update artifact for direct-distribution builds.

#### Scenario: Release produces signed update and appcast
- **WHEN** a `v*` tag triggers the release workflow
- **THEN** a notarized, stapled update ZIP is produced and signed with the Sparkle EdDSA key
- **AND** an `appcast.xml` referencing that ZIP is generated and deployed to the update feed URL
- **AND** the DMG remains available for manual browser download
