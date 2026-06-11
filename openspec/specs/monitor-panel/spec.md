## ADDED Requirements

### Requirement: Centered Cat Companion Column
The popover SHALL display the cyber cat as a centered companion unit in the left column.

#### Scenario: Popover opens
- **WHEN** the user opens the menu bar popover
- **THEN** the speech bubble, cat, and status text are visually centered as one group
- **AND** the bubble does not feel detached from the cat.

### Requirement: Unified Primary Metric Format
Primary metric text SHALL use the `Name: Value` format.

#### Scenario: Hardware metrics render
- **WHEN** metrics are shown in the right list
- **THEN** CPU is formatted like `CPU: 80%`
- **AND** GPU is formatted like `GPU: 68%`
- **AND** memory is formatted like `内存: 62%`
- **AND** no primary metric includes `使用中`.

### Requirement: Curves Only For CPU And GPU
The metric list SHALL show sparklines only for CPU and GPU.

#### Scenario: Metric rows render
- **WHEN** all hardware rows are visible
- **THEN** CPU and GPU rows may show curves
- **AND** memory, storage, network, and battery rows do not show curves.

### Requirement: Correct Metric Labels
Metric labels SHALL be accurate and localized.

#### Scenario: GPU row renders
- **WHEN** GPU metrics are displayed
- **THEN** `Tiler` is shown as `分块`
- **AND** GPU temperature is not shown if it is unavailable.

#### Scenario: Memory row renders
- **WHEN** memory metrics are displayed
- **THEN** the primary value represents usage
- **AND** the secondary pressure value is numeric, not `正常`
- **AND** App and compressed memory are not shown
- **AND** swap memory is shown.

#### Scenario: Network row renders
- **WHEN** network metrics are displayed
- **THEN** only upload and download are shown as secondary metrics.

### Requirement: Consistent Typography
Secondary metric text SHALL use consistent font size, weight, and color treatment across all rows.

#### Scenario: Metric list renders
- **WHEN** secondary metric labels are visible
- **THEN** the labels are visually consistent across CPU, GPU, memory, storage, network, and battery.

### Requirement: Expandable Resource Details
CPU, GPU, memory, and storage rows SHALL reveal additional details below the primary row without changing the default collapsed layout.

#### Scenario: Resource row expands
- **WHEN** the user clicks the CPU, GPU, memory, or storage row
- **THEN** a compact secondary details area is shown below that row
- **AND** the primary row keeps the same icon, title, summary, and chart placement
- **AND** only metrics enabled in settings are displayed

#### Scenario: Detailed metrics render
- **WHEN** expanded details are visible
- **THEN** CPU shows only enabled metrics from: system, user, idle, boot time, temperature
- **AND** GPU shows only enabled metrics from: GPU memory, allocated, render, tiler
- **AND** memory shows only enabled metrics from: used, pressure, swap, total
- **AND** storage shows only enabled metrics from: used, free, total

### Requirement: Configurable Expanded Metrics
Each module's expanded metrics SHALL be configurable through settings.

#### Scenario: CPU metrics configuration
- **WHEN** the user opens CPU module settings
- **THEN** the following metrics are available for selection: system, user, idle, boot time
- **AND** all metrics are checked by default

#### Scenario: GPU metrics configuration
- **WHEN** the user opens GPU module settings
- **THEN** the following metrics are available for selection: GPU memory, allocated, render, tiler
- **AND** all metrics are checked by default

#### Scenario: Memory metrics configuration
- **WHEN** the user opens memory module settings
- **THEN** the following metrics are available for selection: used, pressure, swap, total
- **AND** all metrics are checked by default

#### Scenario: Storage metrics configuration
- **WHEN** the user opens storage module settings
- **THEN** the following metrics are available for selection: used, free, total
- **AND** all metrics are checked by default

#### Scenario: Network metrics configuration
- **WHEN** the user opens network module settings
- **THEN** the following metrics are available for selection: IP address, upload, download
- **AND** all metrics are checked by default

#### Scenario: Battery metrics configuration
- **WHEN** the user opens battery module settings
- **THEN** the following metrics are available for selection: charging power, health, cycle count, temperature
- **AND** all metrics are checked by default

#### Scenario: Battery panel with charging power hidden
- **WHEN** the battery module is expanded
- **AND** charging power is enabled in settings
- **AND** the device is on battery power
- **THEN** charging power is not shown because it has no meaningful value

### Requirement: Automatic Appearance Adaptation
The popover SHALL automatically adapt to the system light or dark appearance.

#### Scenario: Light mode
- **WHEN** the system is in light mode
- **THEN** the popover uses a white frosted glass visual style
- **AND** text remains readable.

#### Scenario: Dark mode
- **WHEN** the system is in dark mode
- **THEN** the popover uses a dark translucent glass visual style
- **AND** text remains readable.

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
