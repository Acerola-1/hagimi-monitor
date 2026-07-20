## Why

HagimiMonitor ships through two channels: the App Store (`HagimiMonitor` scheme, sandboxed) and direct distribution via GitHub Releases (`HagimiMonitorDirect` scheme, notarized). Update handling must differ per channel:

- App Store builds must not check GitHub or drive an in-app download — Apple forbids directing users to install from outside the store, and the store manages updates itself.
- Direct builds previously only checked the GitHub API and told users to open a browser and drag a new DMG into Applications — clumsy for a notarized app.

Now that direct builds are signed + notarized + stapled, they qualify for Sparkle, the de-facto macOS auto-update framework: check → release-notes dialog → in-app download with EdDSA verification → replace and relaunch. Users with poor connectivity still need a manual fallback to download from GitHub in a browser.

## What Changes

- Split the update entry point by distribution channel using `#if DIRECT_DISTRIBUTION`: App Store builds show no update UI and run no update logic.
- Integrate Sparkle (SPM) into the direct build only; App Store build neither links nor embeds Sparkle.
- Replace the old GitHub-API `UpdateChecker` / update banner with Sparkle's standard updater.
- Add an `UpdateService` wrapper around `SPUStandardUpdaterController`, started at launch for background checks.
- About page: primary "Check for Updates" drives Sparkle; an always-visible "Download from GitHub" link is the connectivity fallback.
- Retain a background-detected update in the direct build and show a `NEW` badge beside About in Settings; dismissing Sparkle's window does not clear this reminder.
- Inject Sparkle Info.plist keys (`SUFeedURL`, `SUPublicEDKey`, `SUEnableInstallerLauncherService`) into the direct build's Debug/Release configs only.
- CI: produce a notarized ZIP, sign it with Sparkle's EdDSA key, generate `appcast.xml`, upload the ZIP to the release, and deploy the appcast to GitHub Pages. Keep the DMG for browser download.
- Localize new user-facing text (zh-Hans, en, ja).

## Capabilities

### New Capabilities
- `app-update`: In-app update behavior split by distribution channel — Sparkle auto-update for direct builds with a GitHub fallback, and no in-app update path for App Store builds.

## Impact

- Affected code areas:
  - `hagimi-monitor.xcodeproj`: Sparkle SPM dependency linked to the direct target only; Sparkle Info.plist keys on direct configs.
  - `UpdateService.swift` (new): Sparkle wrapper (`#if DIRECT_DISTRIBUTION`).
  - `AppDelegate`: start Sparkle updater at launch (direct only).
  - `AboutSettingsView`: Sparkle primary button + always-visible GitHub fallback link; App Store shows nothing.
  - `SettingsSidebar`: show a localized `NEW` badge beside About while a direct-build update is available.
  - `SettingsWindowPresenter`, `SettingsRootView`: remove old open-window auto-check and the update banner.
  - Removed: `UpdateChecker.swift`, `UpdateModels.swift`, `UpdateCheckerTests.swift` (superseded by Sparkle).
  - `.github/workflows/release.yml`: ZIP + Sparkle sign + appcast + Pages deploy.
  - `Localizable.xcstrings`: `about.download-from-github`.
- New external dependency: Sparkle 2.x (direct build only). This is HagimiMonitor's first third-party dependency; justified because self-hosted auto-update is impractical to hand-roll and Sparkle is the macOS community standard.

## Operator prerequisites (out of band)

- Generate a Sparkle EdDSA key pair; keep the private key in the `SPARKLE_PRIVATE_KEY` GitHub Secret and put the public key in `INFOPLIST_KEY_SUPublicEDKey` (currently a placeholder).
- Enable GitHub Pages on the `gh-pages` branch so `https://acerola-1.github.io/hagimi-monitor/appcast.xml` is served.
