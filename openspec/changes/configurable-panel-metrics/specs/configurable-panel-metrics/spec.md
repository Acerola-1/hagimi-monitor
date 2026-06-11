## ADDED Requirements

### Requirement: Configurable CPU Metrics
The CPU module SHALL allow users to configure which detailed metrics are displayed when expanded.

#### Scenario: CPU metrics configuration
- **WHEN** the user opens CPU module settings
- **THEN** the following metrics are available for selection:
  - "系统" (system CPU usage)
  - "用户" (user CPU usage)
  - "闲置" (idle CPU percentage)
  - "启动时间" (system uptime)
- **AND** all metrics are checked by default
- **AND** the user can uncheck up to 4 metrics

#### Scenario: CPU panel with filtered metrics
- **WHEN** the CPU module is expanded in the panel
- **AND** only "系统" and "用户" are enabled
- **THEN** only those two metrics are shown in the detail grid

### Requirement: Configurable GPU Metrics
The GPU module SHALL allow users to configure which detailed metrics are displayed when expanded.

#### Scenario: GPU metrics configuration
- **WHEN** the user opens GPU module settings
- **THEN** the following metrics are available for selection:
  - "GPU内存" (GPU memory usage)
  - "已分配" (allocated GPU memory)
  - "渲染" (render utilization)
  - "分块" (tiler utilization)
- **AND** all metrics are checked by default

### Requirement: Configurable Memory Metrics
The memory module SHALL allow users to configure which detailed metrics are displayed when expanded.

#### Scenario: Memory metrics configuration
- **WHEN** the user opens memory module settings
- **THEN** the following metrics are available for selection:
  - "已用" (used memory)
  - "压力" (memory pressure level)
  - "交换已用" (swap used)
  - "总量" (total memory)
- **AND** all metrics are checked by default

### Requirement: Configurable Storage Metrics
The storage module SHALL allow users to configure which detailed metrics are displayed when expanded.

#### Scenario: Storage metrics configuration
- **WHEN** the user opens storage module settings
- **THEN** the following metrics are available for selection:
  - "已用" (used space)
  - "可用" (free space)
  - "总量" (total capacity)
- **AND** all metrics are checked by default

### Requirement: Configurable Network Metrics
The network module SHALL allow users to configure which detailed metrics are displayed when expanded.

#### Scenario: Network metrics configuration
- **WHEN** the user opens network module settings
- **THEN** the following metrics are available for selection:
  - "IP 地址" (network addresses)
  - "上传" (upload speed)
  - "下载" (download speed)
- **AND** all metrics are checked by default

### Requirement: Configurable Battery Metrics
The battery module SHALL allow users to configure which detailed metrics are displayed when expanded.

#### Scenario: Battery metrics configuration
- **WHEN** the user opens battery module settings
- **THEN** the following metrics are available for selection:
  - "充电功率" (charging power)
  - "健康度" (battery health)
  - "循环数" (cycle count)
  - "温度" (temperature)
- **AND** all metrics are checked by default

#### Scenario: Battery panel with charging power hidden
- **WHEN** the battery module is expanded
- **AND** "充电功率" is enabled in settings
- **AND** the device is on battery power (not connected to adapter)
- **THEN** "充电功率" is not shown because it has no meaningful value

## MODIFIED Requirements

### Requirement: Expandable Resource Details
CPU, GPU, memory, and storage rows SHALL reveal additional details below the primary row without changing the default collapsed layout.

#### Scenario: Resource row expands
- **WHEN** the user clicks the CPU, GPU, memory, or storage row
- **THEN** a compact secondary details area is shown below that row
- **AND** the primary row keeps the same icon, title, summary, and chart placement
- **AND** only metrics enabled in settings are displayed

#### Scenario: Detailed metrics render
- **WHEN** expanded details are visible
- **THEN** CPU shows only enabled metrics from: system, user, idle, boot time
- **AND** GPU shows only enabled metrics from: GPU memory, allocated, render, tiler
- **AND** memory shows only enabled metrics from: used, pressure, swap, total
- **AND** storage shows only enabled metrics from: used, free, total
