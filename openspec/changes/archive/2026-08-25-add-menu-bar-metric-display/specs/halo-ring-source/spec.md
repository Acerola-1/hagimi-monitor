## MODIFIED Requirements

### Requirement: Halo Ring Source Configuration
The system SHALL render the menu bar halo ring as a combined-load indicator only. Combined load SHALL use CPU usage, GPU usage, and memory pressure as the ring inputs. The app SHALL NOT expose CPU, GPU, or Memory as user-selectable halo ring sources.

#### Scenario: Default configuration
- **WHEN** the app is launched for the first time
- **THEN** the halo ring is enabled as the default menu bar display
- **AND** the ring displays the weighted average of CPU (40%), GPU (40%), and memory pressure (20%)

#### Scenario: Combined source uses memory pressure
- **WHEN** the halo ring is displayed
- **THEN** the memory contribution is based on system memory pressure, not memory used/total percentage
- **AND** normal pressure contributes 0
- **AND** warning pressure contributes 70
- **AND** critical pressure contributes 100
- **AND** unknown pressure contributes 0

#### Scenario: Legacy source preference is CPU
- **WHEN** an existing user has a persisted halo ring source value of CPU
- **THEN** the app treats the halo ring as combined load
- **AND** the settings UI does not expose CPU as a ring source option

#### Scenario: Legacy source preference is GPU
- **WHEN** an existing user has a persisted halo ring source value of GPU
- **THEN** the app treats the halo ring as combined load
- **AND** the settings UI does not expose GPU as a ring source option

#### Scenario: Legacy source preference is Memory
- **WHEN** an existing user has a persisted halo ring source value of Memory
- **THEN** the app treats the halo ring as combined load
- **AND** the settings UI does not expose Memory as a ring source option

### Requirement: Halo Ring Source Setting UI
The system SHALL display menu bar settings that allow users to choose whether the combined load ring is used as the menu bar display. The system SHALL NOT display a Picker for selecting the halo ring monitoring source.

#### Scenario: Ring display setting is shown
- **WHEN** user opens Settings → General
- **THEN** a menu bar display section is visible
- **AND** the user can choose combined load ring display
- **AND** no source picker with 综合, CPU, GPU, 内存 is shown

## REMOVED Requirements

### Requirement: Memory Pressure Color Mapping
**Reason**: Memory can no longer be selected as a standalone halo ring source. The halo ring always represents combined load, where memory pressure contributes to the combined value.
**Migration**: Users who want to monitor memory directly can select memory usage in menu bar metric display mode.
