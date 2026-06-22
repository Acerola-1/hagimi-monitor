## MODIFIED Requirements

### Requirement: Clear Halo Ring Status-Bar Icon
When the menu bar display mode is combined load ring, the menu bar item SHALL render a halo ring icon that reflects combined system load. The ring arc SHALL represent the combined load value, and the core color SHALL follow the combined load threshold logic.

#### Scenario: Light appearance
- **WHEN** the system is in light mode and combined load ring display is selected
- **THEN** the halo ring icon has sufficient contrast against the menu bar
- **AND** the ring arc and core color remain visible

#### Scenario: Dark appearance
- **WHEN** the system is in dark mode and combined load ring display is selected
- **THEN** the halo ring icon has sufficient contrast against the menu bar
- **AND** the ring arc and core color remain visible without appearing blurry

#### Scenario: Combined load ring display selected
- **WHEN** user selects combined load ring display
- **THEN** the ring arc reflects combined load
- **AND** the core color follows combined load threshold logic

### Requirement: Stable Menu Bar Rendering
The menu bar label SHALL avoid continuously animated SwiftUI views and SHALL render either the combined load ring or the selected compact metric values as one stable menu bar item.

#### Scenario: App runs in the menu bar
- **WHEN** HagimiMonitor is launched
- **THEN** the menu bar item remains visible and stable
- **AND** the app does not disappear due to menu bar label rendering.

#### Scenario: Metric values update
- **WHEN** selected menu bar metric values update during sampling
- **THEN** the menu bar item updates without continuous animation
- **AND** the app continues to expose a single menu bar click target

## ADDED Requirements

### Requirement: Single Menu Bar Button For Multiple Metrics
The system SHALL render all selected menu bar metrics within the same menu bar item rather than creating separate menu bar buttons.

#### Scenario: Multiple metrics selected
- **WHEN** the user selects multiple menu bar metrics
- **THEN** the menu bar shows those metrics together as one label
- **AND** clicking any displayed metric opens the existing monitor panel
- **AND** the system does not create additional menu bar extras for individual metrics
