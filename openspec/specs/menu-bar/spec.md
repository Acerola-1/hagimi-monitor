# menu-bar Specification

## Purpose
Defines the menu bar status-item icon rendering behavior: the halo ring icon that reflects the selected monitoring source, and stable rendering that keeps the app visible in the menu bar.

## Requirements

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

### Requirement: Stable Menu Bar Rendering
The menu bar label SHALL avoid continuously animated SwiftUI views. The label SHALL be hosted in an `NSHostingView` embedded in `NSStatusItem.button` (managed by `FluidPanelController`) instead of a SwiftUI `MenuBarExtra` label, and this hosting SHALL keep the icon visible and stable without causing the process to terminate.

#### Scenario: App runs in the menu bar
- **WHEN** HagimiMonitor is launched
- **THEN** the menu bar icon remains visible and stable
- **AND** the app does not disappear due to menu bar label rendering

#### Scenario: Status item hosts the label view
- **WHEN** the app launches with the self-hosted panel controller
- **THEN** the status item button SHALL host `MenuBarStatusLabel` via `NSHostingView`
- **AND** the icon SHALL remain visible and stable across sampling updates and appearance changes

### Requirement: Menu bar metric prefix localization
Menu bar metric text prefixes (CPU, GPU, MEM, BAT, TEMP, FREE, PWR) SHALL be localized via `String(localized:)` to support non-English abbreviations.

#### Scenario: Japanese system shows metric prefixes
- **WHEN** the system language is Japanese and menu bar displays metric text mode
- **THEN** metric prefixes display Japanese abbreviations
- **AND** no hardcoded English abbreviations are shown

### Requirement: Game HUD 徽章随显隐立即更新
直连版菜单栏图标上的 Game HUD 徽章 SHALL 在浮窗变为可见或隐藏的同一轮界面更新里改变，环形图标与指标文字两种显示模式 SHALL 一致。指标模式的重绘去重 SHALL 把 HUD 显隐纳入比较，不得因数值未变而跳过。徽章 SHALL NOT 等到下一次负载数值变化才更新。告警红点与 HUD 徽章同时存在时 SHALL 只绘制告警。App Store 版 SHALL 不显示该徽章。

#### Scenario: 浮窗出现时徽章点亮
- **WHEN** 直连版的 Game HUD 浮窗从隐藏变为可见，且菜单栏负载数值没有变化
- **THEN** 当前为环形或指标模式的菜单栏图标都出现 HUD 徽章

#### Scenario: 浮窗消失时徽章熄灭
- **WHEN** 直连版的 Game HUD 浮窗从可见变为隐藏，且菜单栏负载数值没有变化
- **THEN** 当前为环形或指标模式的菜单栏图标都去掉 HUD 徽章

#### Scenario: 告警优先
- **WHEN** 菜单栏同时存在告警红点与 Game HUD 运行状态
- **THEN** 状态项只绘制告警红点，不叠画 HUD 徽章

#### Scenario: 商店版没有徽章
- **WHEN** App Store 版运行
- **THEN** 状态项图标不绘制 HUD 徽章
