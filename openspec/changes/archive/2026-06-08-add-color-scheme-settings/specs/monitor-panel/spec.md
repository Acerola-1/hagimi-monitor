## ADDED Requirements

### Requirement: Palette-driven panel colors
The monitor panel SHALL resolve visual colors through the selected monitor palette instead of hardcoding module, surface, or severity colors inside individual row views.

#### Scenario: Panel renders with selected palette
- **WHEN** the monitor panel is shown
- **THEN** module accents, row glass tint, row separators, progress tracks, text colors, display controls, and severity tints are resolved from the selected palette.

### Requirement: Balanced palette
The Balanced palette SHALL preserve the current neutral blue-gray panel structure with restrained module accents.

#### Scenario: Balanced palette renders
- **WHEN** Balanced is the selected color scheme
- **THEN** row glass tint and separators use neutral blue-gray tokens
- **AND** module icons, charts, progress indicators, and display controls use the current restrained accent colors.

### Requirement: Vibrant palette
The Vibrant palette SHALL restore the colorful panel identity by using stronger module accents and module-derived row surfaces while keeping the current layout and typography.

#### Scenario: Vibrant palette renders
- **WHEN** Vibrant is the selected color scheme
- **THEN** CPU, GPU, memory, storage, network, battery, and display sections use distinct stronger accent colors
- **AND** row glass tint and row separators are derived from each section's accent color
- **AND** the panel keeps the current compact layout, spacing, and text hierarchy.

### Requirement: Severity colors remain semantic
Severity colors SHALL remain independent from module accent colors in every color scheme.

#### Scenario: Module row has warning or critical severity
- **WHEN** a module enters warning or critical severity
- **THEN** the severity color comes from the palette's severity tokens
- **AND** it is not derived from the module accent color.
