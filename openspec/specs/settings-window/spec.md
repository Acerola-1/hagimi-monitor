## ADDED Requirements

### Requirement: 紧凑双栏设置容器
设置窗口 SHALL 使用受控双栏布局作为根容器，避免系统 split view 在 Settings 场景中产生异常空白列。

#### Scenario: 设置窗口打开
- **WHEN** 用户从菜单栏面板触发"设置"
- **THEN** 设置窗口以固定侧栏 + 详情区的双栏形态展示
- **AND** 侧栏使用 `.listStyle(.sidebar)` 保持 macOS sidebar 语义
- **AND** 侧栏宽度为 `164`
- **AND** 不出现额外的空白 split 列

### Requirement: 设置窗口尺寸可调
设置窗口 SHALL 允许用户调整大小，并 SHALL 提供合理初始与最小尺寸。

#### Scenario: 窗口尺寸约束
- **WHEN** 设置窗口首次打开
- **THEN** 窗口尺寸为 ideal `600×382`
- **AND** 用户可拖拽至不小于 `560×360`
- **AND** 已被异常拉大的设置窗口会在注册时恢复到紧凑尺寸

### Requirement: 详情页保持精品工具密度
设置窗口 SHALL 使用统一详情页布局，避免 Form 内容随窗口无约束铺宽。

#### Scenario: 详情页内容宽度
- **WHEN** 用户切换任一详情页
- **THEN** 详情页不显示重复的页面级标题或副标题
- **AND** 详情页在右侧详情区顶端对齐
- **AND** 内容不足一屏时不显示滚动条
- **AND** 行控件使用 `.controlSize(.small)` 形成紧凑偏好窗口密度

### Requirement: 侧栏导航项纯净
侧栏 row SHALL 只显示 `Label`，不得嵌入 `Toggle` 或其他交互控件。

#### Scenario: 模块行展示
- **WHEN** 用户在侧栏查看监控模块列表
- **THEN** 每一行仅显示模块图标与标题
- **AND** 行整体可被点击以选中并展示详情
- **AND** 不存在与 `List(selection:)` 冲突的内嵌控件

### Requirement: 详情页使用 Form .grouped
所有详情页 SHALL 以 `Form` 作为容器并使用 `.formStyle(.grouped)`。

#### Scenario: 详情页渲染
- **WHEN** 用户切换到任一侧栏条目
- **THEN** 详情区域以分组 Form 样式呈现
- **AND** label + 控件对使用 `LabeledContent` 而非手拼 HStack
- **AND** 配色、行高、分隔线随系统外观自动适配

### Requirement: 模块详情包含可见性开关与"检测项目"设置组
每个 `MonitorKind` 的详情页 SHALL 包含可见性开关与「检测项目」设置组。

#### Scenario: 打开任一模块详情
- **WHEN** 用户在侧栏选中任一监控模块
- **THEN** 详情页顶部包含"在面板中显示"开关
- **AND** 该顶部开关不得显示额外"显示"分组标题
- **AND** 详情页包含名为"检测项目"的设置组，由 `ForEach(kind.availableMetrics)` 动态渲染为对勾选择行
- **AND** 该设置组至少展示一项（即使是占位）
- **AND** 检测项目不得使用 switch 样式

### Requirement: 可置换检测项目数据模型
应用 SHALL 定义 `MetricSwitch` 数据模型与 `MonitorKind.availableMetrics`，并在 `MonitorSettings` 暴露读写接口。

#### Scenario: 模型契约
- **WHEN** 任意代码访问 `MonitorKind.cpu.availableMetrics`
- **THEN** 返回非空 `[MetricSwitch]`
- **AND** 每个 `MetricSwitch` 拥有稳定 `id`、可本地化 `title`、`isDefault` 默认状态

#### Scenario: 启用状态读写
- **WHEN** 调用 `settings.setMetric("cpu.user", enabled: false, for: .cpu)`
- **THEN** `settings.isMetricEnabled("cpu.user", for: .cpu)` 返回 `false`
- **AND** 该状态写入 UserDefaults key `settings.enabledMetrics.cpu`

#### Scenario: 选择数量上限
- **WHEN** 用户已为某个模块选中 4 个检测项目
- **THEN** 其他未选检测项目不可继续选中
- **AND** 已选检测项目仍可取消
- **AND** UI 显示最多选择 4 项的提示

#### Scenario: 缺失值回退
- **WHEN** UserDefaults 中不存在 `settings.enabledMetrics.cpu`
- **THEN** `settings.isMetricEnabled(id, for: .cpu)` 对 `availableMetrics` 中 `isDefault == true` 的项返回 `true`
- **AND** 对其他 id 返回 `false`

### Requirement: 克制的液态玻璃使用
设置窗口 SHALL 仅在 About 页 App 信息卡片与按钮上使用液态玻璃。

#### Scenario: About 卡片
- **WHEN** 用户进入"关于"页
- **THEN** 顶部 App 信息块包裹在 `GlassEffectContainer` 内
- **AND** 该卡片应用 `glassEffect(.regular, in: .rect(cornerRadius: 14))`
- **AND** "检查更新"或"下载更新"按钮显示在该信息块右侧
- **AND** 其他 Section 不使用任何 `glassEffect`

#### Scenario: 主操作按钮
- **WHEN** 详情页中出现"检查更新"或"下载更新"按钮
- **THEN** 按钮使用 `.buttonStyle(.glassProminent)`

#### Scenario: 次操作按钮
- **WHEN** 详情页中出现发布版本链接或"重置默认值"按钮
- **THEN** 按钮使用 `.buttonStyle(.glass)`

#### Scenario: About 链接精简
- **WHEN** 用户进入"关于"页
- **THEN** 详情页不显示"源代码仓库"行
- **AND** 详情页保留"发布版本"行
- **AND** "发布版本"行与版权文字位于页面底部区域

#### Scenario: Form 内部禁用 glass
- **WHEN** 任何 Section 内部渲染 `LabeledContent`、`Toggle`、`Picker`
- **THEN** 不得对单行或单控件调用 `glassEffect`

### Requirement: 单一导航枚举
应用 SHALL 仅使用一个 `SettingsRoute` 枚举作为设置导航的状态来源。

#### Scenario: 导航状态
- **WHEN** 检索代码库
- **THEN** 不存在死代码 `SettingsSelection` 与未引用的 `SettingsRoute`
- **AND** 侧栏与详情页通过同一个 `SettingsRoute` 枚举耦合

### Requirement: 外部入口兼容
`SettingsWindowPresenter.open(_:tab:)` SHALL 继续支持通过 `SettingsTab` 跳转到指定页面。

#### Scenario: 从面板跳转 About
- **WHEN** 用户点击菜单栏面板中的"关于"按钮
- **THEN** 设置窗口打开并直接选中"关于"页
- **AND** 设置 `SettingsRoute` 为 `.about`

### Requirement: App Store target 隔离
App Store 构建 SHALL 不在侧栏显示"显示器"项，亦不应包含相关详情页代码。

#### Scenario: App Store 构建
- **WHEN** 构建 `HagimiMonitor` scheme
- **THEN** `SettingsRoute` 不包含 `.displayModule`
- **AND** 侧栏不渲染"显示器"行
- **AND** `DisplayModuleSettingsView` 通过 `#if DISPLAY_CONTROL` 隔离
