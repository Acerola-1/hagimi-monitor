## ADDED Requirements

### Requirement: Bundle version display
The Settings About pane SHALL display the app version by reading `CFBundleShortVersionString` from `Bundle.main.infoDictionary`, replacing the current hardcoded version string.

#### Scenario: Version displays current bundle version
- **WHEN** the Settings About pane is shown
- **THEN** the version text reads `CFBundleShortVersionString`
- **AND** displays it as `版本 {version}`

#### Scenario: Version fallback when Bundle info unavailable
- **WHEN** `CFBundleShortVersionString` is unavailable or empty
- **THEN** the version text displays `版本 未知`

### Requirement: Manual GitHub release update check
The app SHALL provide a manual update check in Settings About that queries GitHub Releases for the latest release.

#### Scenario: User starts update check
- **WHEN** the user clicks `检查更新`
- **THEN** the app requests `https://api.github.com/repos/acerola/hagimi-monitor/releases/latest`
- **AND** the update check button is disabled while the request is in progress

#### Scenario: Latest release parsed
- **WHEN** GitHub returns a successful latest release response
- **THEN** the app parses at least `tag_name`, `html_url`, `published_at`, `name`, `body`, and `assets`

### Requirement: Version comparison
The app SHALL compare the current bundle version with the latest release version using normalized numeric version components.

#### Scenario: Tag with v prefix is normalized
- **WHEN** GitHub returns `tag_name` as `v1.2.3`
- **THEN** the app compares it as `1.2.3`

#### Scenario: Multi-digit version components compare correctly
- **WHEN** the current version is `1.9.0`
- **AND** the latest release version is `1.10.0`
- **THEN** the app treats `1.10.0` as newer

#### Scenario: Current version is up to date
- **WHEN** the current version is greater than or equal to the latest release version
- **THEN** the About pane shows that the current app is up to date

### Requirement: Update available state
The app SHALL show update details and a manual download action when a newer GitHub release exists.

#### Scenario: Newer release available
- **WHEN** the latest release version is greater than the current bundle version
- **THEN** the About pane shows the latest version
- **AND** provides a `下载更新` action

#### Scenario: Download action opens browser
- **WHEN** the user clicks `下载更新`
- **THEN** the app opens the selected release asset URL or release page URL in the system browser
- **AND** the app does not attempt to replace or restart itself

### Requirement: Failure state
The app SHALL handle update check failures without crashing and allow retrying.

#### Scenario: Network request fails
- **WHEN** the GitHub request fails
- **THEN** the About pane shows a concise failure message
- **AND** the user can click `检查更新` again

#### Scenario: Release response cannot be parsed
- **WHEN** the GitHub response is missing required version or URL fields
- **THEN** the About pane shows a concise failure message
- **AND** the user can retry later
