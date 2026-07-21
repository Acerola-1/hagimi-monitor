# settings-window Specification

## Purpose
Defines the settings window's localization, layout, and content behavior: how settings UI is displayed and localized across languages.
## Requirements
### Requirement: 设置页面所有文案支持本地化
设置窗口中的所有 UI 文案 SHALL 通过 `String(localized:)` 接入 `Localizable.xcstrings`，支持中英日自动切换。关于页的硬编码文本（Releases 按钮、版权声明）SHALL 同样走本地化系统。

#### Scenario: 侧栏导航显示
- **WHEN** 用户打开设置窗口
- **THEN** 侧栏导航项根据系统语言显示中文、英文或日文
- **AND** "常规" 显示为 "General" / "一般"
- **AND** "监控模块" 显示为 "Modules" / "モジュール"
- **AND** "显示器" 显示为 "Display" / "ディスプレイ"
- **AND** "关于" 显示为 "About" / "概要"
- **AND** "Beta" 标签显示为 "Beta" / "ベータ"

#### Scenario: 关于页面硬编码文本修复
- **WHEN** 用户进入关于页面
- **THEN** "Releases" 按钮标签通过 `String(localized:)` 引用本地化 key
- **AND** "© 2026 Acerola" 版权声明通过 `String(localized:)` 引用本地化 key
- **AND** 日文环境下显示对应日文翻译

#### Scenario: 快速呼出设置本地化
- **WHEN** 用户进入常规设置页
- **THEN** "快速呼出" 显示为 "Quick Access" / "クイックアクセス"
- **AND** "点按录制" 显示为 "Click to record" / "クリックして録音"
- **AND** "按下快捷键…" 显示为 "Press keys…" / "ショートカットキーを押す…"
- **AND** "按下按键" 显示为 "Press key" / "キーを押す"
- **AND** "清除快捷键" 显示为 "Clear shortcut" / "ショートカットをクリア"

### Requirement: 菜单栏面板文案本地化
菜单栏下拉面板中的所有文案 SHALL 支持本地化。

#### Scenario: 面板按钮和标题
- **WHEN** 用户打开菜单栏面板
- **THEN** "活动监视器" 显示为 "Activity Monitor"
- **AND** "设置" 显示为 "Settings"
- **AND** "SYSTEM · LIVE" 通过 `String(localized:)` 引用

#### Scenario: 网络模块标题
- **WHEN** 网络模块在面板中展示
- **THEN** "网络:" 显示为 "Network:"
- **AND** "上传"/"下载" 显示为 "Up"/"Down"

#### Scenario: 电池模块标题
- **WHEN** 电池模块在面板中展示
- **THEN** "电源:" 显示为 "Power:"
- **AND** "适配器" 显示为 "Adapter"
- **AND** "功耗" 显示为 "Power"

#### Scenario: 存储卷名称
- **WHEN** 存储模块展开显示卷详情
- **THEN** "系统盘" 显示为 "System"
- **AND** "已用"/"可用"/"总量" 显示为 "Used"/"Free"/"Total"

### Requirement: 模块详情包含可见性开关与"检测项目"设置组
每个 `MonitorKind` 的详情页 SHALL 包含可见性开关与「检测项目」设置组。

#### Scenario: 打开任一模块详情
- **WHEN** 用户在侧栏选中任一监控模块
- **THEN** 详情页顶部包含"在面板中显示"开关（"Show in Panel"）
- **AND** 该顶部开关不得显示额外"显示"分组标题
- **AND** 详情页包含名为"监测项目"（"Metrics"）的设置组，由 `ForEach(kind.availableMetrics)` 动态渲染为对勾选择行
- **AND** 该设置组至少展示一项（即使是占位）
- **AND** 检测项目不得使用 switch 样式

### Requirement: 紧凑双栏设置容器
设置窗口 SHALL 使用受控双栏布局作为根容器，避免系统 split view 在 Settings 场景中产生异常空白列。

#### Scenario: 设置窗口打开
- **WHEN** 用户从菜单栏面板触发"设置"（"Settings"）
- **THEN** 设置窗口以固定侧栏 + 详情区的双栏形态展示
- **AND** 侧栏使用 `.listStyle(.sidebar)` 保持 macOS sidebar 语义
- **AND** 侧栏宽度为 `164`
- **AND** 不出现额外的空白 split 列

