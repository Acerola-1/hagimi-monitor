## ADDED Requirements

### Requirement: System Event Detection
The statistics system SHALL detect and record significant system events beyond raw metric values.

#### Scenario: CPU sustained high load
- **WHEN** CPU utilization exceeds 85% continuously for 5 minutes
- **THEN** a `cpuSustainedHigh` event is recorded with severity `warning`
- **AND** the event includes the peak CPU value, duration, and top process name (if available)
- **AND** the detection timer resets to avoid duplicate events

#### Scenario: CPU load drops below threshold before 5 minutes
- **WHEN** CPU utilization exceeds 85% but drops below before 5 minutes elapse
- **THEN** no `cpuSustainedHigh` event is recorded
- **AND** the detection timer resets

#### Scenario: Memory pressure escalation
- **WHEN** memory pressure level transitions from `normal` to `warning`
- **THEN** a `memoryPressureUpgrade` event is recorded with severity `warning`
- **AND** the event includes the previous and current pressure levels

#### Scenario: Memory pressure escalation to critical
- **WHEN** memory pressure level transitions to `critical`
- **THEN** a `memoryPressureUpgrade` event is recorded with severity `critical`

#### Scenario: Memory pressure relief
- **WHEN** memory pressure level transitions from `warning` to `normal`
- **THEN** a `memoryPressureDowngrade` event is recorded with severity `info`

#### Scenario: Thermal state escalation
- **WHEN** thermal state transitions from `nominal` to `fair`
- **THEN** a `thermalUpgrade` event is recorded with severity `info`

#### Scenario: Thermal state escalation to serious
- **WHEN** thermal state transitions to `serious` or `critical`
- **THEN** a `thermalUpgrade` event is recorded with severity `warning` or `critical` respectively

#### Scenario: Thermal state relief
- **WHEN** thermal state transitions from a higher to a lower level
- **THEN** a `thermalDowngrade` event is recorded with severity `info`

#### Scenario: Swap usage spike
- **WHEN** swap usage at hour flush is more than double the previous hour's swap usage
- **THEN** a `swapUsageSpike` event is recorded with severity `warning`
- **AND** the event includes the previous and current swap usage values

#### Scenario: Battery overheating
- **WHEN** battery temperature exceeds 40°C
- **THEN** a `batteryOverheat` event is recorded with severity `warning`
- **AND** the event includes the temperature value

#### Scenario: Power source change
- **WHEN** the power source transitions between AC power and battery
- **THEN** a `powerSourceChange` event is recorded with severity `info`
- **AND** the event includes the new power source type

#### Scenario: Low disk space
- **WHEN** free disk space drops below 5 GB
- **THEN** a `diskSpaceLow` event is recorded with severity `warning`

#### Scenario: Critically low disk space
- **WHEN** free disk space drops below 1 GB
- **THEN** a `diskSpaceLow` event is recorded with severity `critical`

### Requirement: Event Persistence
System events SHALL be persisted to SwiftData with configurable retention.

#### Scenario: Event is recorded
- **WHEN** an event is detected
- **THEN** a `SystemEvent` record is created in SwiftData with timestamp, event type, severity, title, detail, and optional top processes, value, previous value, and duration

#### Scenario: Event retention — info events
- **WHEN** an event with severity `info` is older than 30 days
- **THEN** the event is deleted during the next cleanup cycle

#### Scenario: Event retention — warning events
- **WHEN** an event with severity `warning` is older than 90 days
- **THEN** the event is deleted during the next cleanup cycle

#### Scenario: Event retention — critical events
- **WHEN** an event with severity `critical` exists
- **THEN** the event is never automatically deleted

### Requirement: Event Deduplication
Similar events SHALL NOT be recorded in rapid succession.

#### Scenario: CPU sustained high load deduplication
- **WHEN** a `cpuSustainedHigh` event is recorded
- **THEN** the CPU high-load detection timer resets
- **AND** another `cpuSustainedHigh` event cannot be recorded until the timer accumulates another 5 minutes of sustained high load

#### Scenario: State change deduplication
- **WHEN** a state-change event (pressure, thermal) is recorded
- **THEN** the same-direction event cannot be recorded again until the state changes to a different level

#### Scenario: Swap spike deduplication
- **WHEN** a `swapUsageSpike` event is recorded during an hour flush
- **THEN** no additional `swapUsageSpike` event is recorded for the same hour

### Requirement: Event Timeline in Statistics View
The StatisticsView SHALL display recorded events as a timeline below the summary card grid.

#### Scenario: Statistics view loads
- **WHEN** the user opens the Statistics settings tab
- **THEN** an event timeline section is visible below the summary cards
- **AND** events are grouped by day with date headers
- **AND** each event shows time, severity icon, title, and detail
- **AND** critical events show a red warning icon, warning events show a yellow icon, info events show a gray icon

#### Scenario: Event timeline time range
- **WHEN** the user selects a different time range (24h, 7d, 30d)
- **THEN** the event timeline updates to show events within the selected range

#### Scenario: Event with top process information
- **WHEN** an event was recorded with top process information
- **THEN** the timeline row shows the top process names below the event detail

#### Scenario: Event without top process information
- **WHEN** an event was recorded without top process information (panel was not visible)
- **THEN** the timeline row omits the top process section without showing empty space

### Requirement: Event Timeline in HTML Report
The HTML report SHALL include an event timeline section after the module cards.

#### Scenario: Report is generated
- **WHEN** the user opens the HTML report
- **THEN** an event timeline section appears after the module cards for each time range
- **AND** events are displayed in a vertical timeline with nodes
- **AND** each node shows timestamp, event type, detail, and severity color

### Requirement: Event Localization
All event type titles and descriptions SHALL be localized.

#### Scenario: CPU sustained high load event in Chinese
- **WHEN** the system locale is zh-Hans and a CPU sustained high load event is displayed
- **THEN** the event title shows "CPU 持续高负载"

#### Scenario: Memory pressure upgrade event in English
- **WHEN** the system locale is en and a memory pressure upgrade event is displayed
- **THEN** the event title shows "Memory Pressure Escalation"
