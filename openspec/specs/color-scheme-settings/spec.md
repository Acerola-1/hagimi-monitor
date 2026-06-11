## ADDED Requirements

### Requirement: Color scheme setting
The settings window SHALL provide a monitor panel color scheme setting in the General detail view, accessible from the sidebar's "General" entry.

#### Scenario: Settings General detail renders color scheme control
- **WHEN** the user opens Settings and selects "General" in the sidebar
- **THEN** the right-hand detail view shows the Appearance section
- **AND** the Appearance section includes a color scheme control
- **AND** the available options include Balanced and Vibrant.

### Requirement: Balanced default
The app SHALL use the Balanced color scheme when no color scheme preference has been stored.

#### Scenario: First launch without stored color scheme
- **WHEN** the app starts and no color scheme preference exists in user defaults
- **THEN** the selected monitor panel color scheme is Balanced.

### Requirement: Persisted color scheme selection
The app SHALL persist the selected monitor panel color scheme.

#### Scenario: User changes color scheme
- **WHEN** the user selects Vibrant in Settings
- **THEN** the selection is saved
- **AND** the monitor panel uses the Vibrant color scheme.

#### Scenario: App relaunches after color scheme change
- **WHEN** the app starts after the user previously selected Vibrant
- **THEN** the selected monitor panel color scheme remains Vibrant.

### Requirement: Separate from light and dark appearance
The monitor panel color scheme setting SHALL be independent from the existing light and dark appearance setting.

#### Scenario: User changes color scheme only
- **WHEN** the user changes the color scheme setting
- **THEN** the existing theme preference remains unchanged.

#### Scenario: User changes theme preference only
- **WHEN** the user changes the light and dark theme preference
- **THEN** the selected monitor panel color scheme remains unchanged.
