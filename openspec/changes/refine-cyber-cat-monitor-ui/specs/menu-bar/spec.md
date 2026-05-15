## ADDED Requirements

### Requirement: Clear Cat Status-Bar Icon
The menu bar item SHALL render a single cat icon that is clear and recognizable at native macOS menu bar size.

#### Scenario: Light appearance
- **WHEN** the system is in light mode
- **THEN** the cat icon has sufficient contrast against the menu bar
- **AND** the ears/head silhouette remains recognizable.

#### Scenario: Dark appearance
- **WHEN** the system is in dark mode
- **THEN** the cat icon has sufficient contrast against the menu bar
- **AND** the state accent remains visible without appearing blurry.

### Requirement: Stable Menu Bar Rendering
The menu bar label SHALL avoid continuously animated SwiftUI views.

#### Scenario: App runs in the menu bar
- **WHEN** HagimiMonitor is launched
- **THEN** the menu bar icon remains visible and stable
- **AND** the app does not disappear due to menu bar label rendering.

