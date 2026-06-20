## ADDED Requirements

### Requirement: App 根据系统语言自动切换中英文
应用 SHALL 检测系统首选语言，当系统语言为英文时所有 UI 文案显示英文，为中文时显示中文。

#### Scenario: 系统语言为英文
- **WHEN** 用户系统首选语言为英文
- **THEN** 菜单栏面板所有模块标题显示英文（CPU / GPU / Memory / Storage / Network / Battery）
- **AND** 设置页面侧栏导航项显示英文（General / Modules / Display / About）
- **AND** 设置页面所有分组标题和控件标签显示英文
- **AND** 错误提示和状态文本显示英文

#### Scenario: 系统语言为中文
- **WHEN** 用户系统首选语言为简体中文
- **THEN** 所有 UI 文案继续显示中文
- **AND** 行为与当前版本一致

### Requirement: Sampler 指标名称使用中性英文 key
所有 Sampler 返回的 `MonitorMetric.name` SHALL 使用稳定的英文 key，展示层通过模块上下文与 metric id 组合出的本地化 key 翻译为当前语言。

#### Scenario: CPU 模块采样
- **WHEN** CPUSampler 执行采样
- **THEN** 返回的指标 name 为英文 key（"system", "user", "idle", "uptime", "temperature"）
- **AND** 展示层通过 `metric.cpu.system` / `metric.cpu.temperature` 等 key 翻译为 "系统" 或 "System"

#### Scenario: GPU 模块采样
- **WHEN** GPUSampler 执行采样
- **THEN** 返回的指标 name 为英文 key（"gpu-memory", "allocated", "render", "tiler", "temperature"）
- **AND** 展示层通过 `String(localized: "metric.gpu.gpu-memory")` 翻译为 "GPU内存" 或 "GPU Memory"

#### Scenario: Memory 模块采样
- **WHEN** MemorySampler 执行采样
- **THEN** 返回的指标 name 为英文 key（"used", "pressure", "swap-used", "total"）
- **AND** 展示层通过 `String(localized: "metric.memory.used")` 翻译为 "已用" 或 "Used"

#### Scenario: Storage 模块采样
- **WHEN** StorageSampler 执行采样
- **THEN** 返回的指标 name 为英文 key（"used", "free", "total"）
- **AND** 展示层通过 `String(localized: "metric.storage.used")` 翻译为 "已用" 或 "Used"

#### Scenario: Network 模块采样
- **WHEN** NetworkSampler 执行采样
- **THEN** 返回的指标 name 为英文 key（"ip-address", "upload", "download"）
- **AND** 展示层通过 `String(localized: "metric.network.ip-address")` 翻译为 "IP 地址" 或 "IP Address"

#### Scenario: Battery 模块采样
- **WHEN** BatterySampler 执行采样
- **THEN** 返回的指标 name 为英文 key（"charging-power", "health", "cycle-count", "temperature", "adapter", "power"）
- **AND** 展示层通过 `String(localized: "metric.battery.charging-power")` 翻译为 "充电功率" 或 "Charging Power"

#### Scenario: 跨模块重名指标
- **WHEN** 展示层渲染 `temperature`、`used`、`total` 等跨模块复用的 metric id
- **THEN** 必须结合 `MonitorKind` 解析为 `metric.<kind>.<id>`
- **AND** 不得直接使用 `String(localized: metric.name)` 翻译

### Requirement: 设置中的指标配置使用英文 key
`MonitorKind.availableMetrics` 和 `MonitorSettings.enabledMetrics` SHALL 使用英文 key 作为标识，title 通过本地化系统翻译。

#### Scenario: 查看 CPU 可用指标
- **WHEN** 代码访问 `MonitorKind.cpu.availableMetrics`
- **THEN** 返回的 `MetricSwitch.id` 为英文 key（"system", "user", "idle", "uptime", "temperature"）
- **AND** `MetricSwitch.title` 通过 `String(localized:)` 翻译为当前语言

#### Scenario: 查看 GPU 可用指标
- **WHEN** 代码访问 `MonitorKind.gpu.availableMetrics`
- **THEN** 返回的 `MetricSwitch.id` 包含英文 key（"gpu-memory", "allocated", "render", "tiler", "temperature"）
- **AND** `temperature` 默认未勾选，除非温度功能需求另行改变 `isDefault`

#### Scenario: 持久化启用状态
- **WHEN** 用户勾选或取消勾选某个指标
- **THEN** `MonitorSettings.enabledMetrics` 存储英文 key（如 "system"）
- **AND** 语言切换后设置状态保持不变

#### Scenario: 旧数据迁移
- **WHEN** UserDefaults 中存在旧版中文 metric key
- **THEN** 初始化设置时按模块迁移为英文 key
- **AND** 旧 key 与新 key 混合存在时合并去重
- **AND** 迁移结果遵守最多 4 项限制

### Requirement: 电池状态值本地化
电池采样器返回的状态文本（充电状态、电源类型）SHALL 通过本地化系统翻译。

#### Scenario: 电池状态显示
- **WHEN** BatterySampler 返回状态值
- **THEN** 内部使用英文 key（"charging", "on-battery", "ac-power"）
- **AND** 展示层翻译为 "充电中" / "Charging" 等

### Requirement: Responsive Panel Width
The monitor panel SHALL use bounded flexible width constraints instead of a single fixed content width.

#### Scenario: Panel renders collapsed content
- **WHEN** the monitor panel renders its default collapsed module list
- **THEN** the panel uses a configured minimum width, ideal width, and maximum width
- **AND** the content does not require a single hard-coded fixed panel width

#### Scenario: Expanded content needs more horizontal space
- **WHEN** an expanded panel section contains longer labels or values
- **THEN** the panel may grow beyond its ideal width up to the configured maximum width
- **AND** content that still exceeds the maximum width is truncated according to its content type

### Requirement: Adaptive Panel Typography
Panel text SHALL use semantic SwiftUI text styles for adaptable labels, values, captions, buttons, and badges.

#### Scenario: Main metric rows render
- **WHEN** CPU, GPU, memory, storage, network, or battery rows render
- **THEN** row labels, values, and captions use shared semantic text style helpers
- **AND** the implementation does not use fixed point-size fonts for adaptable text in those rows

#### Scenario: Display controls render in the direct build
- **WHEN** the direct-build display controls section appears in the panel
- **THEN** display labels, summaries, badges, and slider labels use semantic text styles aligned with the main panel
- **AND** the section does not keep independent fixed point-size fonts for adaptable text

### Requirement: Intentional Fixed Geometry
The panel SHALL keep fixed dimensions only for stable non-text visual geometry and compact controls.

#### Scenario: Visual controls render
- **WHEN** icons, sparklines, progress meters, sliders, or compact badges render
- **THEN** their fixed dimensions are allowed only when they stabilize scanning, alignment, or control interaction
- **AND** text containers do not use fixed width unless they are part of an explicit compact control contract

### Requirement: Long Panel Content Handling
The panel SHALL handle long metric values, localized labels, display names, network identifiers, and storage volume names without overlapping adjacent UI.

#### Scenario: Network details contain long values
- **WHEN** network details include long IP addresses, interface names, upload values, or download values
- **THEN** the expanded details use a layout that preserves readable label/value relationships
- **AND** overflowing values use explicit truncation or scaling behavior without overlapping other controls

#### Scenario: Storage or display names are long
- **WHEN** a storage volume name or display name exceeds available width
- **THEN** the name is truncated in the middle or otherwise preserves the most useful identifying portions
- **AND** adjacent percentage, badge, slider, or status controls remain visible and aligned

#### Scenario: Localized text is longer than the current language baseline
- **WHEN** localized labels or button titles are longer than their Chinese baseline text
- **THEN** the panel keeps readable spacing and avoids text overlap in collapsed and expanded states

### Requirement: Localizable.xcstrings 包含完整中英文翻译
`Localizable.xcstrings` SHALL 包含所有 UI 文案、指标名称、错误提示、状态文本的中英文翻译。

#### Scenario: 英文系统下打开设置
- **WHEN** 系统在英文环境下运行
- **THEN** `Localizable.xcstrings` 中所有 key 均有英文翻译
- **AND** 不存在未翻译而回退到中文的文本

## MODIFIED Requirements

### Requirement: Correct Metric Labels
Metric labels SHALL be accurate and localized.

#### Scenario: GPU row renders
- **WHEN** GPU metrics are displayed
- **THEN** `Tiler` is shown as localized text ("分块" or "Tiler")
- **AND** GPU temperature is not shown if it is unavailable.

#### Scenario: Memory row renders
- **WHEN** memory metrics are displayed
- **THEN** the primary value represents usage
- **AND** the secondary pressure value is numeric, not `正常`
- **AND** App and compressed memory are not shown
- **AND** swap memory is shown.

#### Scenario: Network row renders
- **WHEN** network metrics are displayed
- **THEN** only upload and download are shown as secondary metrics.

### Requirement: Expandable Resource Details
CPU, GPU, memory, and storage rows SHALL reveal additional details below the primary row without changing the default collapsed layout.

#### Scenario: Resource row expands
- **WHEN** the user clicks the CPU, GPU, memory, or storage row
- **THEN** a compact secondary details area is shown below that row
- **AND** the primary row keeps the same icon, title, summary, and chart placement
- **AND** only metrics enabled in settings are displayed

#### Scenario: Detailed metrics render
- **WHEN** expanded details are visible
- **THEN** CPU shows only enabled metrics from: system, user, idle, uptime, temperature
- **AND** GPU shows only enabled metrics from: gpu-memory, allocated, render, tiler, temperature
- **AND** memory shows only enabled metrics from: used, pressure, swap-used, total
- **AND** storage shows only enabled metrics from: used, free, total

### Requirement: Configurable Expanded Metrics
Each module's expanded metrics SHALL be configurable through settings.

#### Scenario: CPU metrics configuration
- **WHEN** the user opens CPU module settings
- **THEN** the following metrics are available for selection: system, user, idle, uptime, temperature
- **AND** metrics with `isDefault == true` are checked by default
- **AND** optional metrics such as temperature remain unchecked by default

#### Scenario: GPU metrics configuration
- **WHEN** the user opens GPU module settings
- **THEN** the following metrics are available for selection: gpu-memory, allocated, render, tiler, temperature
- **AND** metrics with `isDefault == true` are checked by default
- **AND** optional metrics such as temperature remain unchecked by default

#### Scenario: Memory metrics configuration
- **WHEN** the user opens memory module settings
- **THEN** the following metrics are available for selection: used, pressure, swap-used, total
- **AND** metrics with `isDefault == true` are checked by default

#### Scenario: Storage metrics configuration
- **WHEN** the user opens storage module settings
- **THEN** the following metrics are available for selection: used, free, total
- **AND** metrics with `isDefault == true` are checked by default

#### Scenario: Network metrics configuration
- **WHEN** the user opens network module settings
- **THEN** the following metrics are available for selection: ip-address, upload, download
- **AND** metrics with `isDefault == true` are checked by default

#### Scenario: Battery metrics configuration
- **WHEN** the user opens battery module settings
- **THEN** the following metrics are available for selection: charging-power, health, cycle-count, temperature
- **AND** metrics with `isDefault == true` are checked by default

#### Scenario: Battery panel with charging power hidden
- **WHEN** the battery module is expanded
- **AND** charging power is enabled in settings
- **AND** the device is on battery power
- **THEN** charging power is not shown because it has no meaningful value
