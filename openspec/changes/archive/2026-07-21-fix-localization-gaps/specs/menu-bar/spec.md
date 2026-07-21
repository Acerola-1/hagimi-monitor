## MODIFIED Requirements

### Requirement: Clear Halo Ring Status-Bar Icon
The menu bar item SHALL render a halo ring icon that reflects the user-selected monitoring source. The ring arc SHALL represent the selected metric's value, and the core color SHALL follow the appropriate color logic for the selected source (load threshold for Combined/CPU/GPU, memory pressure level for Memory). The halo ring source titles SHALL be localized via `String(localized:)` for all source types including CPU and GPU.

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

#### Scenario: HaloRingSource title localization consistency
- **WHEN** the halo ring source selector displays available sources
- **THEN** all source titles (Combined, CPU, GPU, Memory) use `String(localized:)`
- **AND** CPU and GPU titles are not hardcoded English strings

## ADDED Requirements

### Requirement: Menu bar metric prefix localization
Menu bar metric text prefixes (CPU, GPU, MEM, BAT, TEMP, FREE, PWR) SHALL be localized via `String(localized:)` to support non-English abbreviations.

#### Scenario: Japanese system shows metric prefixes
- **WHEN** the system language is Japanese and menu bar displays metric text mode
- **THEN** metric prefixes display Japanese abbreviations
- **AND** no hardcoded English abbreviations are shown
