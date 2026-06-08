## MODIFIED Requirements

### Requirement: Clear Cat Status-Bar Icon
The menu bar item SHALL render a halo ring icon that reflects the user-selected monitoring source. The ring arc SHALL represent the selected metric's value, and the core color SHALL follow the appropriate color logic for the selected source (load threshold for Combined/CPU/GPU, memory pressure level for Memory).

#### Scenario: Light appearance
- **WHEN** the system is in light mode
- **THEN** the halo ring icon has sufficient contrast against the menu bar
- **AND** the ring arc and core color remain visible

#### Scenario: Dark appearance
- **WHEN** the system is in dark mode
- **THEN** the halo ring icon has sufficient contrast against the menu bar
- **AND** the ring arc and core color remain visible without appearing blurry

#### Scenario: Source changed to Memory
- **WHEN** user changes halo ring source to Memory
- **THEN** the ring arc reflects memory usage percentage
- **AND** the core color reflects system memory pressure level instead of usage threshold
