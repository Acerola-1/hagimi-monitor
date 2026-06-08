## ADDED Requirements

### Requirement: Halo Ring Source Configuration
The system SHALL allow users to select which metric the menu bar halo ring monitors, from four options: Combined (CPU 40% + GPU 40% + memory pressure 20%), CPU, GPU, and Memory. The default SHALL be Combined.

#### Scenario: Default configuration
- **WHEN** the app is launched for the first time
- **THEN** the halo ring source is set to "Combined"
- **AND** the ring displays the weighted average of CPU (40%), GPU (40%), and memory pressure (20%)

#### Scenario: Combined source uses memory pressure
- **WHEN** the halo ring source is Combined
- **THEN** the memory contribution is based on system memory pressure, not memory used/total percentage
- **AND** normal pressure contributes 0
- **AND** warning pressure contributes 70
- **AND** critical pressure contributes 100
- **AND** unknown pressure contributes 0

#### Scenario: User selects CPU
- **WHEN** user changes halo ring source to "CPU"
- **THEN** the ring arc reflects the CPU usage percentage
- **AND** the ring core color follows the load threshold logic (<35 idle, <65 working, <85 busy, ≥85 stressed)

#### Scenario: User selects GPU
- **WHEN** user changes halo ring source to "GPU"
- **THEN** the ring arc reflects the GPU usage percentage
- **AND** the ring core color follows the load threshold logic

#### Scenario: User selects Memory
- **WHEN** user changes halo ring source to "Memory"
- **THEN** the ring arc reflects the memory used/total percentage
- **AND** the ring core color follows the system memory pressure level (normal → idle green, warning → busy orange, critical → stressed red, unknown → working light green)

#### Scenario: Setting persistence
- **WHEN** user changes the halo ring source
- **THEN** the selection is persisted to UserDefaults
- **AND** the selection is restored on next app launch

### Requirement: Halo Ring Source Setting UI
The system SHALL display a "负载环" section in the General settings pane with a Picker for selecting the monitoring source.

#### Scenario: Picker displays all options
- **WHEN** user opens Settings → General
- **THEN** a "负载环" section is visible below "外观"
- **AND** a "监测项目" Picker shows options: 综合, CPU, GPU, 内存
- **AND** the current selection is displayed

### Requirement: Memory Pressure Color Mapping
When the halo ring source is Memory, the ring core color SHALL be determined by the system memory pressure level (kern.memorystatus_vm_pressure_level), NOT by the usage percentage threshold.

#### Scenario: Memory pressure is normal
- **WHEN** halo ring source is Memory AND system memory pressure level is normal
- **THEN** the ring core color is idle green

#### Scenario: Memory pressure is warning
- **WHEN** halo ring source is Memory AND system memory pressure level is warning
- **THEN** the ring core color is busy orange

#### Scenario: Memory pressure is critical
- **WHEN** halo ring source is Memory AND system memory pressure level is critical
- **THEN** the ring core color is stressed red

#### Scenario: Memory pressure is unknown
- **WHEN** halo ring source is Memory AND system memory pressure level cannot be determined
- **THEN** the ring core color is working light green (fallback)
