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
GPU, memory, and storage rows SHALL reveal additional details below the primary row without changing the default collapsed layout.

#### Scenario: Resource row expands
- **WHEN** the user clicks the GPU, memory, or storage row
- **THEN** a compact secondary details area is shown below that row
- **AND** the primary row keeps the same icon, title, summary, and chart placement.

#### Scenario: Detailed metrics render
- **WHEN** expanded details are visible
- **THEN** GPU includes GPU memory usage
- **AND** memory includes memory pressure
- **AND** storage includes accurate used storage and total capacity.

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
