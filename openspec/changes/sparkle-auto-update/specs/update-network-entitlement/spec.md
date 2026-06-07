## ADDED Requirements

### Requirement: Network client entitlement for update checks
The sandboxed HagimiMonitor target SHALL allow outbound network requests for manual GitHub release update checks.

#### Scenario: Entitlement file includes network client access
- **WHEN** the HagimiMonitor target is built
- **THEN** the built app uses an entitlements file
- **AND** the entitlements include `com.apple.security.app-sandbox` set to true
- **AND** the entitlements include `com.apple.security.network.client` set to true

#### Scenario: GitHub update check is allowed by sandbox
- **WHEN** the user checks for updates
- **THEN** the app can make an outbound HTTPS request to GitHub without sandbox permission errors
