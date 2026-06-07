## ADDED Requirements

### Requirement: Release workflow triggered by version tag
The project SHALL have a GitHub Actions workflow (`.github/workflows/release.yml`) that triggers on `v*` tag pushes. The workflow SHALL build, sign, notarize, generate appcast, and create a GitHub Release.

#### Scenario: Tag push triggers release workflow
- **WHEN** a tag matching `v*` is pushed
- **THEN** the release workflow starts automatically

### Requirement: Apple code signing in CI
The workflow SHALL sign the app bundle using a Developer ID Application certificate. Signing order SHALL be: XPC Services → Sparkle helper tools → Sparkle.framework → App bundle. The workflow SHALL NOT use `codesign --deep`.

#### Scenario: App signed with correct order
- **WHEN** the signing step executes
- **THEN** XPC Services are signed first with `-o runtime`
- **AND** Sparkle.framework is signed before the app
- **AND** the app is signed last with `--entitlements` and `--options runtime`
- **AND** `codesign --verify` passes for all signed components

### Requirement: Apple notarization in CI
The workflow SHALL submit the app for Apple notarization using `xcrun notarytool submit` and staple the notarization ticket using `xcrun stapler staple`.

#### Scenario: App notarized and stapled
- **WHEN** the notarization step completes
- **THEN** `spctl -a -t exec -vv` confirms the app passes Gatekeeper validation

### Requirement: GitHub Release creation
The workflow SHALL create a GitHub Release with the built and signed app artifact (ZIP or DMG). The release SHALL include auto-generated release notes.

#### Scenario: GitHub Release created with artifacts
- **WHEN** the workflow completes
- **THEN** a GitHub Release exists for the tag with the app artifact attached
- **AND** the appcast.xml is uploaded to the "appcast" release

### Requirement: Required GitHub Secrets
The workflow SHALL require the following GitHub Secrets: `APPLE_SIGNING_CERT_P12` (base64-encoded Developer ID P12), `APPLE_SIGNING_CERT_PASSWORD` (P12 password), `NOTARY_API_KEY_PATH`, `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER`, `SPARKLE_EDDSA_PRIVATE_KEY`.

#### Scenario: All secrets configured
- **WHEN** the repository admin configures all required secrets
- **THEN** the release workflow can sign, notarize, and generate appcast without manual intervention
