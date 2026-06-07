## ADDED Requirements

### Requirement: appcast.xml format for GitHub Releases
The project SHALL provide an appcast.xml file conforming to Sparkle's RSS-based feed format. Each item SHALL include: `sparkle:version` (build number), `sparkle:shortVersionString`, `sparkle:minimumSystemVersion` (set to 26.0), `sparkle:hardwareRequirements` (set to arm64), `sparkle:edSignature`, and an `enclosure` element with `url` pointing to a GitHub Release asset.

#### Scenario: appcast.xml contains valid Sparkle feed
- **WHEN** Sparkle fetches the feed URL
- **THEN** it parses a valid RSS 2.0 document with Sparkle namespace
- **AND** each item has a valid `enclosure url` pointing to `https://github.com/acerola/hagimi-monitor/releases/download/...`
- **AND** each item has a valid `sparkle:edSignature`

### Requirement: appcast.xml hosted on GitHub Release asset
The appcast.xml SHALL be hosted as a GitHub Release asset on a dedicated release named "appcast". The `SUFeedURL` in Info.plist SHALL point to `https://github.com/acerola/hagimi-monitor/releases/download/appcast/appcast.xml`.

#### Scenario: Feed URL resolves to appcast.xml
- **WHEN** the app checks the configured `SUFeedURL`
- **THEN** it receives the current appcast.xml content

#### Scenario: appcast.xml updated on new release
- **WHEN** a new version is released via GitHub Actions
- **THEN** the appcast.xml is regenerated with the new version entry
- **AND** uploaded to the "appcast" release with `--clobber`

### Requirement: EdDSA key pair generation
The project SHALL use Sparkle's `generate_keys` tool to create an EdDSA key pair. The public key SHALL be stored in Info.plist as `SUPublicEDKey`. The private key SHALL be stored in GitHub Secrets as `SPARKLE_EDDSA_PRIVATE_KEY` for CI use.

#### Scenario: Public key configured in Info.plist
- **WHEN** the app is built
- **THEN** Info.plist contains `SUPublicEDKey` with the EdDSA public key value

#### Scenario: Private key available in CI
- **WHEN** GitHub Actions release workflow runs
- **THEN** it reads `SPARKLE_EDDSA_PRIVATE_KEY` from GitHub Secrets to sign the update

### Requirement: generate_appcast in CI
The GitHub Actions release workflow SHALL use Sparkle's `generate_appcast` tool to automatically generate appcast.xml with correct EdDSA signatures and download URLs from the built artifacts.

#### Scenario: appcast generated from release artifacts
- **WHEN** the release workflow runs
- **THEN** `generate_appcast` processes the built DMG/ZIP and produces appcast.xml
- **AND** the generated appcast.xml includes valid `sparkle:edSignature` for each item
