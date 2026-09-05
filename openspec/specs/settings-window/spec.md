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
设置窗口 SHALL 使用受控双栏布局作为根容器，避免系统 split view 在 Settings 场景中产生异常空白列；窗口宽度 SHALL 固定为 660pt 以保障指标卡内部呼吸感与排版空间。

#### Scenario: 设置窗口打开
- **WHEN** 用户从菜单栏面板触发"设置"（"Settings"）
- **THEN** 设置窗口以固定侧栏 + 详情区的双栏形态展示
- **AND** 侧栏使用 `.listStyle(.sidebar)` 保持 macOS sidebar 语义
- **AND** 侧栏宽度为 `164`
- **AND** 窗口宽度固定为 `660` pt
- **AND** 不出现额外的空白 split 列

### Requirement: 深链打开设置窗口直达目标标签页
从应用菜单、面板等入口带目标标签页打开设置窗口时，窗口 SHALL 直达该标签页，包括每次应用启动后的首次打开。

#### Scenario: 启动后首次深链打开
- **WHEN** 应用刚启动、本会话尚未打开过设置窗口，用户通过菜单"关于"入口打开设置
- **THEN** 设置窗口打开并直达"关于"标签页，而非默认页

#### Scenario: 面板统计入口深链
- **WHEN** 面板可见时用户点击统计入口
- **THEN** 设置窗口打开并直达统计相关标签页（无论窗口此前是否打开过）

### Requirement: 快捷键录入器随窗口关闭拆除
快捷键录入交互的所有事件拦截与快捷键禁用状态，SHALL 在设置窗口关闭时被完全拆除——包括录制进行中被关窗的情形。

#### Scenario: 录制中途关闭设置窗口
- **WHEN** 用户开始录入快捷键后未按确认/取消，直接关闭设置窗口
- **THEN** 按键监视器被移除，应用内其他窗口的按键输入不受影响
- **AND** 全局快捷键恢复可用

### Requirement: 权限轮询在终态停止
权限请求的轮询 SHALL 在获得授权或确认被拒绝后停止；SHALL NOT 在权限状态已无变化可能时以固定频率无限期轮询。

#### Scenario: 用户拒绝权限
- **WHEN** 用户在系统弹窗中拒绝输入监控/辅助功能权限
- **THEN** 轮询在合理时限内停止
- **AND** 应用后续不再以固定频率查询该权限状态

### Requirement: 遥测可被用户关闭
匿名使用数据上报（如有）SHALL 在设置中提供明确的退出开关，关闭后 SHALL 停止一切上报。

#### Scenario: 用户关闭遥测
- **WHEN** 用户在设置中关闭使用数据上报
- **THEN** 应用不再发送任何遥测数据
- **AND** 该偏好在重启后保持

### Requirement: 侧边栏语义分组与存储路由高亮维持
设置侧栏 SHALL 按语义组织为逻辑分组（如通用设置、监控模块、扩展功能、关于支持），并且当应用导航至存储管理（`.storage`）子页面时，侧栏中的数据统计条目 SHALL 保持高亮激活状态，避免选中态丢失；硬件 SSD 监控模块的侧栏及详情标题 SHALL 显示为「磁盘」/「Disk」，避免与应用「存储管理」同名冲突。

#### Scenario: 存储管理子页面导航时侧栏高亮不丢失
- **WHEN** 用户在数据统计详情页点击「存储管理」进入 `.storage` 页面
- **THEN** 侧边栏中的「数据统计」（"Statistics"）项保持激活高亮状态
- **AND** 侧栏不出现全项未选中的空白无激活态

#### Scenario: 侧边栏语义分组展示
- **WHEN** 用户打开设置窗口
- **THEN** 侧边栏展示具有视觉区分的逻辑分组标题（常规、模块、扩展、关于）
- **AND** 硬件存储模块标题显示为「磁盘」（英文 "Disk"）

### Requirement: 菜单栏指标单列表排序与选择
通用设置中的菜单栏指标配置 SHALL 采用单一内联可重排列表形态，整合启用勾选与显示顺序调整，消除上下双列表的分裂与篇幅浪费。

#### Scenario: 菜单栏指标勾选与拖拽重排
- **WHEN** 用户在通用设置页调整菜单栏指标
- **THEN** 所有候选指标呈现在同一列表中
- **AND** 勾选激活的指标可通过手柄拖拽直接调整先后顺序
- **AND** 最多允许同时勾选 4 项指标
