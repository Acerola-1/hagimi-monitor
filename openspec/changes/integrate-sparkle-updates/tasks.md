## 1. Channel Split

- [x] 1.1 Gate the About page update UI behind `#if DIRECT_DISTRIBUTION`; App Store shows nothing.
- [x] 1.2 Remove the open-window auto-check from `SettingsWindowPresenter`.
- [x] 1.3 Remove the update banner from `SettingsRootView`.

## 2. Sparkle Dependency

- [x] 2.1 Add Sparkle SPM package linked to the direct target only.
- [x] 2.2 Inject `SUFeedURL` / `SUPublicEDKey` (placeholder) / `SUEnableInstallerLauncherService` into direct Debug/Release configs.
- [x] 2.3 Replace the `SUPublicEDKey` placeholder with the real public key (needs operator key generation).

## 3. Code Integration

- [x] 3.1 Add `UpdateService` wrapping `SPUStandardUpdaterController` (`#if DIRECT_DISTRIBUTION`).
- [x] 3.2 Start the updater at launch in `AppDelegate` (direct only).
- [x] 3.3 About page: Sparkle primary button + always-visible "Download from GitHub" fallback.
- [x] 3.4 Remove dead `UpdateChecker` / `UpdateModels` / update banner / tests.
- [x] 3.5 Add `about.download-from-github` localization (zh-Hans, en, ja).
- [x] 3.6 Retain Sparkle update availability and show a localized `NEW` badge beside About in direct builds.

## 4. CI & Hosting

- [x] 4.1 Produce a notarized update ZIP for Sparkle.
- [x] 4.2 Sign the ZIP and generate `appcast.xml` via `generate_appcast` + `SPARKLE_PRIVATE_KEY`.
- [x] 4.3 Upload the ZIP to the GitHub Release; keep the DMG for browser download.
- [x] 4.4 Deploy `appcast.xml` to the `gh-pages` branch.
- [x] 4.5 Enable GitHub Pages on `gh-pages` (operator action).
- [x] 4.6 Set the `SPARKLE_PRIVATE_KEY` GitHub Secret (operator action).

## 5. Verification

- [x] 5.1 Build `HagimiMonitorDirect` (Debug) with Sparkle linked & embedded.
- [x] 5.2 Clean-build `HagimiMonitor` (App Store) and confirm no Sparkle framework/link (otool).
- [ ] 5.3 End-to-end: tag a release, confirm appcast is served and an older build auto-updates.
- [ ] 5.4 Manual: About page fallback link opens GitHub Releases.
