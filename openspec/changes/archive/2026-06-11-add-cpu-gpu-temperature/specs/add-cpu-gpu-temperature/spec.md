## ADDED Requirements

### Requirement: GPU Temperature Metric
The GPU sampler SHALL expose temperature as an optional metric in the expanded detail view.

#### Scenario: GPU temperature is available
- **WHEN** the GPU sampler reads `PerformanceStatistics` from `IOAccelerator`
- **AND** the `"Temperature(C)"` key is present
- **THEN** a temperature metric is added to the GPU module's metrics array
- **AND** the value is formatted as `"XX°C"`

#### Scenario: GPU temperature is unavailable
- **WHEN** the GPU sampler reads `PerformanceStatistics`
- **AND** the `"Temperature(C)"` key is absent
- **THEN** no temperature metric is added

### Requirement: CPU Temperature Metric
The CPU sampler SHALL read CPU temperature from the System Management Controller (SMC).

#### Scenario: CPU temperature on Apple Silicon
- **WHEN** the CPU sampler runs on Apple Silicon
- **THEN** it reads SMC temperature keys: `Tp09`, `Tp0T`, `Tp01`, `Tp05`, `Tp0D`, `Tp0H`, `Tp0L`, `Tp0P`, `Tp0X`, `Tp0b`
- **AND** calculates the average of available sensors
- **AND** formats the value as `"XX°C"`

#### Scenario: CPU temperature unavailable
- **WHEN** SMC connection fails or no temperature keys are readable
- **THEN** the temperature metric shows `"--"`

### Requirement: Temperature as Optional Setting
Temperature metrics for CPU and GPU SHALL appear in module settings as optional, unchecked by default.

#### Scenario: CPU module settings
- **WHEN** the user opens CPU module settings
- **THEN** "温度" appears in the metrics list
- **AND** it is unchecked by default

#### Scenario: GPU module settings
- **WHEN** the user opens GPU module settings
- **THEN** "温度" appears in the metrics list
- **AND** it is unchecked by default

#### Scenario: User enables temperature
- **WHEN** the user checks "温度" in CPU or GPU settings
- **THEN** the metric is added to `enabledMetrics`
- **AND** the expanded panel shows the temperature value

### Requirement: Temperature Display in Panel
When enabled, temperature SHALL appear in the module's expanded detail grid.

#### Scenario: CPU expanded with temperature
- **WHEN** the CPU module is expanded
- **AND** "温度" is enabled in settings
- **THEN** the detail grid shows "温度" with the current CPU temperature

#### Scenario: GPU expanded with temperature
- **WHEN** the GPU module is expanded
- **AND** "温度" is enabled in settings
- **THEN** the detail grid shows "温度" with the current GPU temperature
