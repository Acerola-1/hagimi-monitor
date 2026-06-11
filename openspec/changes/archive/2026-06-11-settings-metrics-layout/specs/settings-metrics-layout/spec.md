## ADDED Requirements

### Requirement: Metrics Section Label
The metrics selection section in module settings SHALL use the label "监测项目".

#### Scenario: Module settings page renders
- **WHEN** the user navigates to any module's settings page
- **THEN** the metrics section header displays "监测项目"
- **AND** the caption below the section remains unchanged

### Requirement: Two-Column Metrics Grid
The metrics selection list SHALL display metrics in a two-column grid layout.

#### Scenario: Metrics grid renders
- **WHEN** the metrics section is visible in module settings
- **THEN** metrics are arranged in a grid with 2 columns
- **AND** each metric cell shows the checkmark and title
- **AND** the grid uses appropriate spacing between items

#### Scenario: Metrics grid with odd number of items
- **WHEN** a module has an odd number of metrics (e.g., 3)
- **THEN** the last item is left-aligned in the first column
- **AND** the second column of the last row is empty

### Requirement: Preserved Interaction
The two-column grid SHALL preserve all existing interaction behaviors.

#### Scenario: User toggles a metric
- **WHEN** the user clicks any metric cell in the two-column grid
- **THEN** the metric is toggled on or off
- **AND** the checkmark appears or disappears
- **AND** the 4-item limit is still enforced
- **AND** disabled metrics (at limit) are visually dimmed
