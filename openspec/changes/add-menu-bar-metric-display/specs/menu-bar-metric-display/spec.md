## ADDED Requirements

### Requirement: Menu Bar Metric Display Mode
The system SHALL allow users to choose a menu bar metric display mode where selected metric values are rendered together in the menu bar as one combined status item.

#### Scenario: Metric mode renders selected values
- **WHEN** the user selects metric display mode and chooses multiple supported metrics
- **THEN** the menu bar label displays the selected metric values together
- **AND** clicking any part of the label opens the existing monitor panel

#### Scenario: Metric mode with one selected metric
- **WHEN** the user selects metric display mode and chooses exactly one supported metric
- **THEN** the menu bar label displays that single metric value
- **AND** the label still behaves as the same single menu bar item

### Requirement: Curated Menu Bar Metric Choices
The system SHALL expose only menu-bar-friendly metrics for metric display mode. The initial supported choices SHALL include CPU usage, GPU usage, memory usage, battery level, network download rate, network upload rate, CPU temperature, and storage free space when their source data is available.

#### Scenario: Settings show supported menu bar metrics
- **WHEN** the user opens the menu bar display settings
- **THEN** the metric picker/list shows the supported menu bar metric choices
- **AND** it does not expose unsuitable detail metrics such as IP address, public IP, uptime, total memory, battery cycle count, or battery health

#### Scenario: Metric value unavailable
- **WHEN** a selected metric cannot currently provide a value
- **THEN** the menu bar label shows a compact unavailable placeholder for that metric
- **AND** the menu bar item remains visible and clickable

### Requirement: Metric Selection Limit
The system SHALL require metric display mode to have at least one selected metric and SHALL allow no more than four selected metrics.

#### Scenario: Default metric selection
- **WHEN** metric display mode is enabled without an existing selected metric list
- **THEN** CPU usage is selected by default

#### Scenario: Maximum selected metrics reached
- **WHEN** the user has selected four menu bar metrics
- **THEN** additional unselected metrics cannot be selected until one selected metric is removed
- **AND** the settings UI communicates that the maximum is four

#### Scenario: Prevent empty metric selection
- **WHEN** metric display mode is active and the user attempts to remove the last selected metric
- **THEN** the system prevents an empty selection or restores the default CPU usage selection

### Requirement: Metric Ordering
The system SHALL preserve the user-selected order of menu bar metrics and render metrics left-to-right in that order.

#### Scenario: User reorders metrics
- **WHEN** the user changes the order of selected menu bar metrics in settings
- **THEN** the menu bar label updates to reflect the new order
- **AND** the order is restored after app relaunch

### Requirement: Compact Metric Formatting
The system SHALL format menu bar metrics with compact values suitable for limited menu bar width.

#### Scenario: Percentage metric formatting
- **WHEN** a selected metric is a percentage value such as CPU, GPU, memory, or battery
- **THEN** the menu bar label displays it as a whole-number percentage such as `42%`

#### Scenario: Temperature formatting
- **WHEN** a selected metric is CPU temperature
- **THEN** the menu bar label displays compact temperature text such as `88°`

#### Scenario: Network rate formatting
- **WHEN** a selected metric is network upload or download rate
- **THEN** the menu bar label displays a compact directional rate such as `↑320K` or `↓2.4M`

#### Scenario: Storage free formatting
- **WHEN** a selected metric is storage free space
- **THEN** the menu bar label displays compact capacity text such as `128G`

### Requirement: Menu Bar Display Settings UI
The system SHALL provide settings for choosing between combined load ring display and metric display, selecting metrics, ordering metrics, and previewing the resulting menu bar label.

#### Scenario: User opens menu bar display settings
- **WHEN** the user opens Settings → General
- **THEN** a menu bar display section is visible
- **AND** the section offers combined load ring display and metric display choices

#### Scenario: Metric mode settings are shown
- **WHEN** metric display mode is selected
- **THEN** the settings UI shows metric selection controls
- **AND** it shows the selected count with the maximum count
- **AND** it shows ordering controls for selected metrics
- **AND** it shows a preview of the menu bar label

#### Scenario: Ring mode settings are simplified
- **WHEN** combined load ring display is selected
- **THEN** the settings UI does not show a ring source picker
- **AND** it communicates that the ring represents combined load

### Requirement: Menu Bar Metric Persistence
The system SHALL persist menu bar display mode and selected metric order across app launches.

#### Scenario: Persist metric mode
- **WHEN** the user selects metric display mode and chooses an ordered metric list
- **THEN** the display mode and metric order are saved
- **AND** the same mode and metric order are restored on next app launch

#### Scenario: Persist ring mode
- **WHEN** the user selects combined load ring display
- **THEN** the ring display mode is saved
- **AND** the app launches with the combined load ring on next app launch
