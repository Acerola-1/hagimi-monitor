## ADDED Requirements

### Requirement: Numeric Metric Exposure
Samplers SHALL expose raw numeric values on `MonitorMetric.numericValue` for any metric that must be persisted by the statistics system, so that `StatisticsRecorder` can extract values without parsing formatted strings.

#### Scenario: Sampler exposes numeric value alongside display string
- **WHEN** a sampler constructs a metric whose value is a formatted string (e.g. `"2.3 GB"`, `"23%"`)
- **THEN** the metric also carries `numericValue` holding the raw number (bytes, percentage, or count)
- **AND** existing display logic that reads `value` continues to work unchanged

#### Scenario: Recorder extracts numeric value
- **WHEN** StatisticsRecorder reads a metric via `metricNumeric(_:key:)`
- **THEN** it returns the `numericValue` if present, or nil if absent
- **AND** it does not attempt to parse the formatted `value` string

### Requirement: Swap Usage Statistics
The statistics system SHALL record swap memory usage per hour and per day.

#### Scenario: Memory sampler produces swap metric
- **WHEN** MemorySampler produces a sample with `swap-used` metric carrying `numericValue` in bytes
- **THEN** StatisticsRecorder accumulates the swap usage value in the current hour's SampleBucket
- **AND** on hour boundary flush, the average swap usage is written to `HourlySample.swapUsed`
- **AND** on daily aggregation, the average swap usage is written to `DailyAggregate.swapUsed`

#### Scenario: Query swap statistics
- **WHEN** StatisticsAggregator queries hourly or daily data
- **THEN** `StatisticsDataPoint.swapUsed` contains the average swap usage in bytes for that period
- **AND** `StatisticsSummary.avgSwapUsed` contains the overall average swap usage

### Requirement: Memory Pressure Level Statistics
The statistics system SHALL record the most severe memory pressure level observed per hour and per day.

#### Scenario: Memory sampler produces pressure level metric
- **WHEN** MemorySampler produces a sample with `pressure-level` metric exposing `MemoryPressureLevel.rawValue` (0=normal, 1=warning, 2=critical, 3=unknown)
- **THEN** StatisticsRecorder tracks the maximum (most severe) pressure level seen in the current hour's SampleBucket
- **AND** on hour boundary flush, the peak pressure level is written to `HourlySample.memoryPressureLevel`
- **AND** on daily aggregation, the peak pressure level is written to `DailyAggregate.memoryPressureLevel`

### Requirement: Thermal State Statistics
The statistics system SHALL record the most severe system thermal pressure state observed per hour and per day.

#### Scenario: System thermal state is nominal throughout the hour
- **WHEN** `ProcessInfo.processInfo.thermalState` returns `.nominal` for every sample in the hour
- **THEN** `HourlySample.thermalState` is 0

#### Scenario: System thermal state reaches serious during the hour
- **WHEN** the thermal state is `.nominal` for part of the hour and `.serious` (raw value 2) for another part
- **THEN** `HourlySample.thermalState` is 2 (the most severe state observed, not the average)
- **AND** a single `.critical` sample in the hour results in `HourlySample.thermalState` of 3

### Requirement: Swap Activity Statistics
The statistics system SHALL record swap-in and swap-out page count deltas per hour and per day.

#### Scenario: Memory sampler produces swapins/swapouts metrics
- **WHEN** MemorySampler produces a sample with `swapins` and `swapouts` metrics carrying cumulative page counts as `numericValue`
- **THEN** StatisticsRecorder records the delta (current - previous cumulative) in the current hour's SampleBucket, reusing the `lastCumulative` mechanism used for network/storage bytes
- **AND** on flush, `HourlySample.swapins` and `HourlySample.swapouts` contain the delta page count for the hour
- **AND** on daily aggregation, the hourly deltas are summed

### Requirement: CPU Breakdown Statistics
The statistics system SHALL record CPU system, user, and idle breakdown per hour and per day.

#### Scenario: CPU sampler produces system/user/idle metrics
- **WHEN** CPUSampler produces a sample with `system`, `user`, and `idle` metrics carrying `numericValue`
- **THEN** StatisticsRecorder accumulates each value separately in the SampleBucket
- **AND** on flush, `HourlySample.cpuSystem`, `cpuUser`, `cpuIdle` contain the average percentages

### Requirement: CPU Temperature Statistics
The statistics system SHALL record CPU temperature per hour and per day when DISPLAY_CONTROL is enabled.

#### Scenario: CPU sampler produces temperature metric
- **WHEN** CPUSampler produces a sample with `temperature` metric (DISPLAY_CONTROL build) carrying `numericValue`
- **THEN** StatisticsRecorder accumulates the temperature value in the SampleBucket
- **AND** on flush, `HourlySample.cpuTemperature` contains the average temperature in Celsius

#### Scenario: DISPLAY_CONTROL is not enabled
- **WHEN** the build does not include DISPLAY_CONTROL
- **THEN** `HourlySample.cpuTemperature` remains nil

### Requirement: GPU Detail Statistics
The statistics system SHALL record GPU memory usage and render/tiler utilization per hour and per day.

#### Scenario: GPU sampler produces detail metrics
- **WHEN** GPUSampler produces a sample with `gpu-memory`, `render`, and `tiler` metrics carrying `numericValue`
- **THEN** StatisticsRecorder accumulates each value in the SampleBucket, skipping nil for conditionally-absent `render`/`tiler`
- **AND** on flush, `HourlySample.gpuMemoryUsed`, `gpuRenderUtil`, `gpuTilerUtil` contain the averages

### Requirement: Battery Statistics
The statistics system SHALL record battery health, cycle count, temperature, and power source ratio per hour and per day.

#### Scenario: Battery sampler produces health and cycle metrics
- **WHEN** BatterySampler produces a sample with `health`, `cycle-count`, `temperature`, and `type` metrics carrying `numericValue`
- **THEN** StatisticsRecorder accumulates health and temperature values, records the latest cycle count, and counts battery vs AC power samples
- **AND** on flush, `HourlySample.batteryHealth`, `batteryCycleCount`, `batteryTemperature`, `onBatteryPower` are populated

### Requirement: Network Peak Rate Statistics
The statistics system SHALL record peak upload and download rates per hour and per day.

#### Scenario: Network sampler produces rate metrics
- **WHEN** NetworkSampler produces a sample with `upload` and `download` rate metrics carrying `numericValue` in bytes/sec
- **THEN** StatisticsRecorder tracks the maximum rate seen in the current hour's SampleBucket
- **AND** on flush, `HourlySample.netPeakDownload` and `netPeakUpload` contain the peak rates in bytes/sec

### Requirement: Disk Free Space Statistics
The statistics system SHALL record disk free space per hour and per day.

#### Scenario: Storage sampler produces free space metric
- **WHEN** StorageSampler produces a sample with `free` metric carrying `numericValue` in bytes
- **THEN** StatisticsRecorder records the latest free space value in the SampleBucket
- **AND** on flush, `HourlySample.diskFree` contains the free space in bytes

### Requirement: Disk I/O Peak Rate Statistics
The statistics system SHALL record peak disk read and write rates per hour and per day.

#### Scenario: Storage sampler produces I/O rate metrics
- **WHEN** StorageSampler produces a sample with `disk-read-rate` and `disk-write-rate` metrics carrying `numericValue` in bytes/sec (computed from cumulative byte deltas)
- **THEN** StatisticsRecorder tracks the maximum rate seen in the current hour's SampleBucket
- **AND** on flush, `HourlySample.diskPeakRead` and `diskPeakWrite` contain the peak rates in bytes/sec

### Requirement: Backward Compatibility
All new statistics fields SHALL be Optional and gracefully handle nil values from existing data.

#### Scenario: Querying data recorded before this change
- **WHEN** StatisticsAggregator queries HourlySample or DailyAggregate records created before the new fields were added
- **THEN** all new fields return nil
- **AND** existing fields (avg, peak, low, bytesInDelta, etc.) return their original values
- **AND** no query or aggregation produces errors or crashes

#### Scenario: SwiftData lightweight migration
- **WHEN** the app launches with the new model schema for the first time
- **THEN** SwiftData automatically adds the new Optional columns without data loss
- **AND** existing records remain intact
