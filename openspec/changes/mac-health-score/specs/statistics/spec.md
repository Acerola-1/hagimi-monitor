## ADDED Requirements

### Requirement: Health Score Calculation
The statistics system SHALL compute a composite health score from 0 to 100 based on weighted average of per-dimension health values.

#### Scenario: All dimensions have data
- **WHEN** CPU, Memory, GPU, Disk, Swap, Memory Pressure, and Thermal data are all available for the requested time range
- **THEN** the health score is computed as `100 * (0.25*s_cpu + 0.25*s_mem + 0.15*s_gpu + 0.10*s_disk + 0.10*s_swap + 0.10*s_pressure + 0.05*s_thermal)`
- **AND** each dimension health value is computed per the dimension-specific formula

#### Scenario: Some dimensions have nil data
- **WHEN** one or more dimensions have nil data for the requested time range
- **THEN** those dimensions are excluded from the weighted average
- **AND** the remaining dimensions' weights are proportionally redistributed so they sum to 1.0
- **AND** the health score reflects only the available dimensions

#### Scenario: Thermal state is critical
- **WHEN** the average thermal state for the time range is `.critical`
- **THEN** the health score is capped at 20 regardless of other dimension values
- **AND** `HealthScore.thermalCapped` is `true`

### Requirement: CPU Health Dimension
The CPU health dimension SHALL measure CPU utilization inversely.

#### Scenario: CPU at 0% utilization
- **WHEN** average CPU utilization is 0%
- **THEN** CPU health value is 1.0

#### Scenario: CPU at 80% utilization
- **WHEN** average CPU utilization is 80%
- **THEN** CPU health value is 0.20

### Requirement: Memory Health Dimension
The Memory health dimension SHALL measure memory utilization inversely.

#### Scenario: Memory at 50% utilization
- **WHEN** average memory utilization is 50%
- **THEN** Memory health value is 0.50

### Requirement: GPU Health Dimension
The GPU health dimension SHALL measure GPU utilization inversely.

#### Scenario: GPU at 30% utilization
- **WHEN** average GPU utilization is 30%
- **THEN** GPU health value is 0.70

### Requirement: Disk Health Dimension
The Disk health dimension SHALL measure disk utilization inversely.

#### Scenario: Disk at 70% utilization
- **WHEN** average disk utilization is 70%
- **THEN** Disk health value is 0.30

### Requirement: Swap Health Dimension
The Swap health dimension SHALL penalize swap usage relative to physical memory.

#### Scenario: No swap usage
- **WHEN** average swap usage is 0 bytes
- **THEN** Swap health value is 1.0

#### Scenario: Swap usage equals physical memory
- **WHEN** average swap usage equals total physical memory
- **THEN** Swap health value is 0.0

#### Scenario: Swap usage is half of physical memory
- **WHEN** average swap usage is 50% of total physical memory
- **THEN** Swap health value is 0.5

### Requirement: Memory Pressure Health Dimension
The Memory Pressure health dimension SHALL map pressure levels to discrete health values.

#### Scenario: Memory pressure is normal
- **WHEN** average memory pressure level is 0 (normal)
- **THEN** Pressure health value is 1.0

#### Scenario: Memory pressure is warning
- **WHEN** average memory pressure level is 1 (warning)
- **THEN** Pressure health value is 0.5

#### Scenario: Memory pressure is critical
- **WHEN** average memory pressure level is 2 (critical)
- **THEN** Pressure health value is 0.0

### Requirement: Thermal Health Dimension
The Thermal health dimension SHALL map thermal states to discrete health values.

#### Scenario: Thermal state is nominal
- **WHEN** average thermal state is 0 (nominal)
- **THEN** Thermal health value is 1.0

#### Scenario: Thermal state is fair
- **WHEN** average thermal state is 1 (fair)
- **THEN** Thermal health value is 0.75

#### Scenario: Thermal state is serious
- **WHEN** average thermal state is 2 (serious)
- **THEN** Thermal health value is 0.5

#### Scenario: Thermal state is critical
- **WHEN** average thermal state is 3 (critical)
- **THEN** Thermal health value is 0.0
- **AND** the overall health score is capped at 20

### Requirement: Health Level Classification
The health score SHALL be classified into one of five levels.

#### Scenario: Score is 87
- **WHEN** the computed health score is 87
- **THEN** the level is `.excellent`

#### Scenario: Score is 72
- **WHEN** the computed health score is 72
- **THEN** the level is `.good`

#### Scenario: Score is 55
- **WHEN** the computed health score is 55
- **THEN** the level is `.fair`

#### Scenario: Score is 38
- **WHEN** the computed health score is 38
- **THEN** the level is `.poor`

#### Scenario: Score is 15
- **WHEN** the computed health score is 15
- **THEN** the level is `.critical`

### Requirement: Health Score Time Range
The health score SHALL support multiple time ranges using historical statistics data.

#### Scenario: 1-hour range
- **WHEN** the user selects the 1-hour time range
- **THEN** the health score is computed from the current PendingBucket and the most recent HourlySample

#### Scenario: 24-hour range
- **WHEN** the user selects the 24-hour time range
- **THEN** the health score is computed from the 24 most recent HourlySample records

#### Scenario: 7-day range
- **WHEN** the user selects the 7-day time range
- **THEN** the health score is computed from the 7 most recent DailyAggregate records

### Requirement: Health Score Display in Statistics View
The StatisticsView SHALL display the health score prominently above the summary card grid.

#### Scenario: Statistics view loads
- **WHEN** the user opens the Statistics settings tab
- **THEN** a health score section is visible at the top of the view
- **AND** the section contains a large ring visualization showing the score
- **AND** the section contains a segmented picker for time range selection (1h, 24h, 7d, 30d)
- **AND** the section contains per-dimension breakdown rows

#### Scenario: Time range changes
- **WHEN** the user selects a different time range
- **THEN** the health score and all dimension values update to reflect the new range

### Requirement: Health Score in HTML Report
The HTML report SHALL include a health score card before the per-module cards.

#### Scenario: Report is generated
- **WHEN** the user opens the HTML report
- **THEN** a health score card appears as the first card
- **AND** the card shows the score as an SVG ring chart
- **AND** the card shows per-dimension breakdown bars
- **AND** for multi-day ranges, a health score trend line is shown

### Requirement: Health Score Localization
All health score user-visible text SHALL be localized.

#### Scenario: Chinese locale
- **WHEN** the system locale is zh-Hans
- **THEN** the health score title displays "Mac 健康评分"
- **AND** level labels display "优秀", "良好", "一般", "较差", "糟糕"

#### Scenario: English locale
- **WHEN** the system locale is en
- **THEN** the health score title displays "Mac Health Score"
- **AND** level labels display "Excellent", "Good", "Fair", "Poor", "Critical"
