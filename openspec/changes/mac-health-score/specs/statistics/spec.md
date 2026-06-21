## ADDED Requirements

### Requirement: Health Score Calculation
The statistics system SHALL compute a composite health score from 0 to 100 based on weighted average of per-dimension health values.

#### Scenario: All dimensions have data
- **WHEN** CPU, GPU, Disk, Memory Pressure, and Thermal data are all available for the requested time range
- **THEN** the health score is computed as `100 * (0.35*s_cpu + 0.20*s_gpu + 0.15*s_disk + 0.25*s_pressure + 0.05*s_thermal)`
- **AND** each dimension health value is computed per the dimension-specific formula
- **NOTE** Memory usage % and Swap are excluded — macOS intentionally fills RAM and uses swap as normal memory management; only pressure level matters

#### Scenario: Some dimensions have nil data
- **WHEN** one or more dimensions have nil data for the requested time range
- **THEN** those dimensions are excluded from the weighted average
- **AND** the remaining dimensions' weights are proportionally redistributed so they sum to 1.0
- **AND** the health score reflects only the available dimensions

#### Scenario: No data available for range
- **WHEN** the requested time range has no HourlySample records and no pending bucket
- **THEN** the health score returns `isDataAvailable: false`
- **AND** dimensions array is empty
- **AND** score is 0
- **AND** UI displays a "not enough data" placeholder instead of the score ring

#### Scenario: Thermal state sustained serious or worse
- **WHEN** the weighted average thermal state for the time range is >= 2.0 (sustained serious or worse)
- **THEN** the health score is capped at 40 regardless of other dimension values
- **AND** `HealthScore.thermalCapped` is `true`

### Requirement: CPU Health Dimension
The CPU health dimension SHALL use a piecewise curve that is gentle at low load and steep at high load.

#### Scenario: CPU at 0% utilization
- **WHEN** average CPU utilization is 0%
- **THEN** CPU health value is 1.0

#### Scenario: CPU at 50% utilization
- **WHEN** average CPU utilization is 50%
- **THEN** CPU health value is approximately 0.893 (piecewise curve: 1.0 - (50/70)*0.15)

#### Scenario: CPU at 80% utilization
- **WHEN** average CPU utilization is 80%
- **THEN** CPU health value is approximately 0.575 (piecewise curve: 0.85 - ((80-70)/20)*0.55)

#### Scenario: CPU at 100% utilization
- **WHEN** average CPU utilization is 100%
- **THEN** CPU health value is 0.0

### Requirement: Memory Usage Excluded
Memory usage percentage SHALL NOT be a health score dimension. macOS intentionally fills RAM with file caches and compressed pages; high usage is normal behavior. Memory health is represented solely by the Memory Pressure dimension.

### Requirement: Swap Excluded
Swap usage SHALL NOT be a health score dimension. macOS uses swap as a normal part of its memory management hierarchy; swap presence does not indicate a problem.

### Requirement: GPU Health Dimension
The GPU health dimension SHALL measure GPU utilization inversely.

#### Scenario: GPU at 30% utilization
- **WHEN** average GPU utilization is 30%
- **THEN** GPU health value is 0.70

### Requirement: Disk Health Dimension
The Disk health dimension SHALL use threshold-based scoring: no penalty while free space is sufficient, dropping linearly only below 15% free.

#### Scenario: Disk at 70% utilization (30% free)
- **WHEN** average disk utilization is 70% (30% free space)
- **THEN** Disk health value is 1.0 (free >= 15%, no penalty)

#### Scenario: Disk at 92% utilization (8% free)
- **WHEN** average disk utilization is 92% (8% free space)
- **THEN** Disk health value is approximately 0.533 (8/15)

### Requirement: Memory Pressure Health Dimension
The Memory Pressure health dimension SHALL use the weighted average of pressure levels (excluding unknown=3), interpolated continuously.

#### Scenario: Memory pressure average is 0 (all normal)
- **WHEN** weighted average memory pressure level is 0
- **THEN** Pressure health value is 1.0

#### Scenario: Memory pressure average is 1 (all warning)
- **WHEN** weighted average memory pressure level is 1
- **THEN** Pressure health value is 0.5

#### Scenario: Memory pressure average is 0.5 (mixed normal/warning)
- **WHEN** weighted average memory pressure level is 0.5
- **THEN** Pressure health value is 0.75

#### Scenario: Memory pressure average is 2 (all critical)
- **WHEN** weighted average memory pressure level is 2
- **THEN** Pressure health value is 0.0

### Requirement: Thermal Health Dimension
The Thermal health dimension SHALL use the weighted average of thermal states, interpolated piecewise to match discrete mapping at integer values.

#### Scenario: Thermal average is 0 (all nominal)
- **WHEN** weighted average thermal state is 0
- **THEN** Thermal health value is 1.0

#### Scenario: Thermal average is 1 (all fair)
- **WHEN** weighted average thermal state is 1
- **THEN** Thermal health value is 0.75

#### Scenario: Thermal average is 2 (all serious)
- **WHEN** weighted average thermal state is 2
- **THEN** Thermal health value is 0.5
- **AND** the overall health score is capped at 40 (avgThermalState >= 2.0 threshold)

#### Scenario: Thermal average is 3 (all critical)
- **WHEN** weighted average thermal state is 3
- **THEN** Thermal health value is 0.0
- **AND** the overall health score is capped at 40

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

#### Scenario: Statistics view loads with data
- **WHEN** the user opens the Statistics settings tab and data exists for the selected range
- **THEN** a health score section is visible at the top of the view
- **AND** the section contains a large ring visualization showing the score
- **AND** the section contains a trend sparkline beneath the ring (if ≥2 data points)
- **AND** the section contains an info button that opens a tips popover
- **AND** the section contains per-dimension breakdown rows with raw value and health bar

#### Scenario: Statistics view loads without data
- **WHEN** the user opens the Statistics settings tab and no data exists for the selected range
- **THEN** the health score section shows a "not enough data" placeholder card
- **AND** no score ring or dimension rows are displayed

#### Scenario: Time range changes
- **WHEN** the user selects a different time range
- **THEN** the health score and all dimension values update to reflect the new range
- **AND** daily ranges (7d/30d/1y) include today's live data so scores are comparable with 24h

### Requirement: Dimension Raw Value Display
Each dimension row SHALL display both the original metric value and the health degree.

#### Scenario: CPU dimension displays
- **WHEN** CPU average utilization is 32%
- **THEN** the row shows "CPU" on the left, "32%" as rawText on the right
- **AND** the health bar shows the CPU piecewise health value
- **AND** the health number (e.g., "93") appears at the bar end

#### Scenario: Swap dimension displays
- **WHEN** average swap usage is 2.3 GB
- **THEN** the rawText shows "2.3 GB"

#### Scenario: Pressure dimension displays
- **WHEN** weighted average pressure level is 0.3 (mostly normal)
- **THEN** the rawText shows the localized level label (e.g., "正常" / "Normal")

### Requirement: Health Score Tips Popover
An info button next to the health title SHALL open a popover explaining the scoring system.

#### Scenario: Info button clicked
- **WHEN** the user clicks the info.circle button next to "Mac 健康评分"
- **THEN** a popover appears with the title "评分说明"
- **AND** the popover explains the weighted average formula, each dimension's meaning, and the thermal cap
- **AND** the popover is scrollable (max height 360)

### Requirement: Health Score Trend
The health score section SHALL display a trend sparkline showing per-bucket score over time.

#### Scenario: 24h range with multiple hours
- **WHEN** the user views the 24h health score with hourly data
- **THEN** a sparkline beneath the ring shows the per-hour health score trend
- **AND** the line color transitions from green (high) to yellow (mid) to red (low)

#### Scenario: 7d range with multiple days
- **WHEN** the user views the 7d health score
- **THEN** the sparkline shows per-day health scores (including today's live data)

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
