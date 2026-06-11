## ADDED Requirements

### Requirement: 设置页面所有文案支持本地化
设置窗口中的所有 UI 文案 SHALL 通过 `String(localized:)` 接入 `Localizable.xcstrings`，支持中英文自动切换。

#### Scenario: 侧栏导航显示
- **WHEN** 用户打开设置窗口
- **THEN** 侧栏导航项根据系统语言显示中文或英文
- **AND** "常规" 显示为 "General"
- **AND** "监控模块" 显示为 "Modules"
- **AND** "显示器" 显示为 "Display"
- **AND** "关于" 显示为 "About"

#### Scenario: 常规设置页面
- **WHEN** 用户进入"常规"设置页
- **THEN** 所有分组标题和控件标签显示英文
- **AND** "开机自启" 显示为 "Launch at Login"
- **AND** "外观" 显示为 "Appearance"
- **AND** "主题" 显示为 "Theme"
- **AND** "配色" 显示为 "Color Scheme"
- **AND** "菜单栏" 显示为 "Menu Bar"
- **AND** "负载环" 显示为 "Halo Ring"
- **AND** 主题选项 "跟随系统"/"浅色"/"深色" 显示为 "System"/"Light"/"Dark"
- **AND** 配色选项 "平衡"/"活力" 显示为 "Balanced"/"Vibrant"

#### Scenario: 模块设置页面
- **WHEN** 用户进入任一模块设置页
- **THEN** "在面板中显示" 显示为 "Show in Panel"
- **AND** "监测项目" 显示为 "Metrics"
- **AND** "最多选择 N 项用于主面板展示" 显示为 "Select up to N metrics to display in the panel."
- **AND** "重置默认值" 显示为 "Reset Defaults"

#### Scenario: 显示器设置页面（Direct build）
- **WHEN** 用户进入"显示器"设置页（Direct build）
- **THEN** "包含内置显示器" 显示为 "Include Built-in Display"
- **AND** "控制项" 显示为 "Controls"
- **AND** "亮度"/"音量"/"对比度" 显示为 "Brightness"/"Volume"/"Contrast"

#### Scenario: 关于设置页面
- **WHEN** 用户进入"关于"设置页
- **THEN** "发布版本" 显示为 "Release Version"
- **AND** "检查更新" 显示为 "Check for Updates"
- **AND** "正在检查..." 显示为 "Checking..."
- **AND** "已是最新" 显示为 "Up to Date"
- **AND** "再次检查" 显示为 "Check Again"
- **AND** "下载更新" 显示为 "Download Update"
- **AND** "重试" 显示为 "Retry"
- **AND** "未知" 显示为 "Unknown"

### Requirement: 菜单栏面板文案本地化
菜单栏下拉面板中的所有文案 SHALL 支持本地化。

#### Scenario: 面板按钮和标题
- **WHEN** 用户打开菜单栏面板
- **THEN** "活动监视器" 显示为 "Activity Monitor"
- **AND** "设置" 显示为 "Settings"
- **AND** "SYSTEM · LIVE" 保持英文（已是英文）

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

## MODIFIED Requirements

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
