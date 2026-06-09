## ADDED Requirements

### Requirement: Stable Dark Mode Readability Across macOS 26 And 27
The monitor panel SHALL keep metric text, charts, progress indicators, and command labels readable in dark mode on both macOS 26 and macOS 27, including when the desktop or underlying windows contain bright or high-contrast content.

#### Scenario: Dark mode over bright background
- **WHEN** the user opens the menu bar popover in dark mode over a bright or complex background
- **THEN** primary metric values, secondary metric values, charts, and command labels remain readable
- **AND** background content does not visually compete with the panel content.

#### Scenario: Dark mode on macOS 27
- **WHEN** the app runs on macOS 27 and the system applies stronger Liquid Glass rendering
- **THEN** the panel preserves a subdued monitoring-tool appearance
- **AND** row highlights and button highlights do not become the dominant visual elements.

### Requirement: Single Outer Glass Shell
The monitor panel SHALL avoid stacking multiple full-panel glass or material surfaces that create visibly mismatched outer and inner corner radii.

#### Scenario: Popover corners render
- **WHEN** the user opens the menu bar popover
- **THEN** the visible outer panel corners read as one coherent shell
- **AND** the panel does not show a second full-size rounded rectangle with mismatched corner geometry.

### Requirement: Inset Reading Surface
The monitor panel SHALL provide a subdued reading surface inside the system menu-window shell when needed for readability, and that surface MUST be inset from the outer shell so it does not compete with the window border or corner radius.

#### Scenario: Reading surface renders
- **WHEN** the panel is shown with an internal readability surface
- **THEN** the surface improves text contrast and background separation
- **AND** it does not touch the outer window corners.

### Requirement: Controlled Metric Row Glass
Metric rows SHALL prioritize readability and visual unity over individual Liquid Glass prominence.

#### Scenario: Metric rows render on macOS 27
- **WHEN** metric rows are displayed on macOS 27
- **THEN** each row remains visually grouped with the panel
- **AND** specular highlights, refractive edges, or hover effects do not overpower the metric label, value, chart, or progress indicator.

### Requirement: Quiet Panel Command Buttons
The Activity Monitor and Settings buttons SHALL remain secondary commands and MUST NOT visually dominate the panel in macOS 27 dark mode.

#### Scenario: Command buttons render
- **WHEN** the user opens the panel in dark mode
- **THEN** the command buttons remain discoverable and clickable
- **AND** their glass or hover treatment does not draw more attention than the hardware metrics.
