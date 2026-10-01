# monitor-panel Specification

## Purpose
Defines the monitor panel's localization, layout, and content behavior: how metrics are displayed, localized, and configured across languages.

## Requirements

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
The panel SHALL handle long metric values, localized labels, display names, network identifiers, and storage volume names without overlapping adjacent UI. Metric grid 的整行/半行布局 SHALL 是静态登记与格式化契约的纯函数,不依赖运行时对当前值的文本测量。

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

#### Scenario: 布局不随当前值与面板宽度重排
- **WHEN** 面板宽度在支持区间内调整,或指标值在会话期间发生长度变化
- **THEN** 每个指标格的整行/半行归属与排列保持稳定
- **AND** 判定基准取最窄支持面板宽度推导的半格内容宽,使全区间判定一致成立

### Requirement: Localizable.xcstrings 包含完整中英日翻译
`Localizable.xcstrings` SHALL 包含所有 UI 文案、指标名称、错误提示、状态文本的中英日翻译。

#### Scenario: 英文系统下打开设置
- **WHEN** 系统在英文环境下运行
- **THEN** `Localizable.xcstrings` 中所有 key 均有英文翻译
- **AND** 不存在未翻译而回退到中文的文本

#### Scenario: 日文系统下使用面板
- **WHEN** 系统在日文环境下运行
- **THEN** `Localizable.xcstrings` 中所有 key 均有日文翻译
- **AND** 不存在未翻译而回退到中文或英文的文本

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

CPU、GPU、风扇、内存、磁盘、网络、电源、蓝牙及显示器的所有可用展开内容 SHALL 纳入同一面板运动行为。展开 SHALL 保持原版行头布局、正式内容组件和模块语义；可见指标与设备以当前设置、真实数据及渠道能力为准，不采用 Demo 的固定数字或精简内容替代。

#### Scenario: Resource row expands
- **WHEN** 用户点击任一可展开模块行头
- **THEN** 明细在该行下方揭示，行头保留原有图标、标题、主值和趋势/状态位置
- **AND** 只展示当前启用且可用的指标与内容，保留用户顺序

#### Scenario: Detailed metrics render
- **WHEN** 展开区呈现指标、逐核/逐风扇内容、设备列表或进程榜
- **THEN** 使用正式模块的指标目录、格式化、图标、状态与缺失值语义
- **AND** 保留原有静态半行/整行宽度契约及进程列表规则，不以缩放、截断指标文本或删除内容维持动画

#### Scenario: 专用模块与嵌套内容展开
- **WHEN** 用户展开网络、电源、蓝牙、显示器或显示器内的设备档案
- **THEN** 保留网络状态与诊断、电源分页与功率流、蓝牙逐设备内容，以及各渠道支持的显示器信息/控制
- **AND** 各级内容及分页高度变化参与同一连贯运动

#### Scenario: 模块或设备不可用
- **WHEN** 渠道或硬件不支持某模块，或设备断开、数据暂缺
- **THEN** 按原有规则隐藏或显示缺失状态，不伪造数值或新增权限
- **AND** 受影响的布局不会残留空白卡片、重复指标或错误展开状态

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

### Requirement: 菜单栏面板文案本地化
菜单栏下拉面板中的所有文案 SHALL 支持本地化，包括面板标题、右键菜单和钉住/关闭操作。

#### Scenario: 面板按钮和标题
- **WHEN** 用户打开菜单栏面板
- **THEN** "活动监视器" 显示为 "Activity Monitor" / "アクティビティモニタ"
- **AND** "设置" 显示为 "Settings" / "設定"
- **AND** "SYSTEM · LIVE" 通过 `String(localized:)` 引用

#### Scenario: 面板钉住和关闭操作
- **WHEN** 用户右键点击面板标题栏
- **THEN** "钉住面板" 显示为 "Pin Panel" / "パネルをピン留め"
- **AND** "取消钉住" 显示为 "Unpin Panel" / "ピン留めを解除"
- **AND** "关闭面板" 显示为 "Close Panel" / "パネルを閉じる"

### Requirement: 展开区指标行序
模块展开区指标网格 SHALL 将半行两列网格排在前面,热压力合并行与整行指标沉底;半行数量为奇数时,空缺格 SHALL 落在模块末尾。

#### Scenario: 整行与半行混合
- **WHEN** 某模块展开区同时含整行与半行指标
- **THEN** 半行两列网格先渲染,热压力合并行与整行格随其后
- **AND** 半行数量为奇数时,模块末尾最后一格留空而非中部出现空洞

#### Scenario: 语义配对的整行指标
- **WHEN** 两个整行指标存在语义配对关系(如 Wi-Fi 信号与网关延迟)
- **THEN** 二者在整行区内保持相邻与既定先后顺序

### Requirement: core-split 指标格的 P/E 瓦片取代
CPU 展开区 SHALL 以 P/E 占用瓦片展示分组占用;core-split 指标被瓦片取代后 SHALL 不再进入指标网格,避免同源数据双重渲染。

#### Scenario: 逐核数据可用时 P/E 瓦片取代 core-split 格
- **WHEN** CPU 采样侧产出逐核数据且 core-split 指标处于开启态
- **THEN** CPU 展开区以 P/E 占用瓦片展示分组占用(与 core-split 同源同口径)
- **AND** core-split 指标格不再进入指标网格,同源数值不重复渲染

#### Scenario: core-split 关闭或无逐核数据
- **WHEN** 用户关闭 core-split 指标,或采样侧未产出逐核数据
- **THEN** P/E 占用瓦片与逐核环形图一并隐藏,不发生取代

### Requirement: 网络 TOP 列表按负责进程归并
网络进程列表与其他进程列表（CPU/内存/GPU/磁盘）口径一致：子进程与助手进程（浏览器渲染进程、各类 Helper）的流量 SHALL 归并进其宿主应用，按宿主应用的聚合流量排序。

#### Scenario: 多进程浏览器的流量归并
- **WHEN** 浏览器以多个子进程同时产生网络流量
- **THEN** 网络 TOP 列表显示一条宿主应用条目，流量为所有子进程之和
- **AND** 归并后的总量参与排序与截断，不被拆散到截断线以下

### Requirement: 模块指标关闭选择跨重启保留
用户在设置中关闭某模块的指标后，该选择 SHALL 在应用重启后保持；关闭全部指标的选择同样保持，SHALL NOT 被启动时的兼容性迁移静默还原为默认指标集。

#### Scenario: 关闭部分指标后重启
- **WHEN** 用户关闭内存模块的部分指标并重启应用
- **THEN** 面板与菜单栏只显示未被关闭的指标

#### Scenario: 关闭模块全部指标后重启
- **WHEN** 用户关闭某模块的全部指标并重启应用
- **THEN** 该模块保持无指标状态，不复活默认指标
- **AND** 用户可随时在设置中重新启用

### Requirement: 经典毛玻璃的层次与可读性

面板 SHALL 采用经典毛玻璃风格，保留底座、模块行卡、指标内衬和文字/状态的视觉层次；浅色和深色、平衡和活力配色在真实浅色/深色及复杂背景下 SHALL 可辨识，不将原型简化配色作为正式 UI 的替代。

#### Scenario: 浅色白背景对照
- **WHEN** 浅色面板在白色应用页面前展开
- **THEN** 外框、行卡、明细内衬与页面背景可区分，文字、图标和状态色保持清晰
- **AND** 录像或截图包含周围真实背景，不用窗口单独录制结果替代此项验收

#### Scenario: 深色与不同配色对照
- **WHEN** 深色面板在浅色或深色背景前使用平衡或活力配色
- **THEN** 正文、辅助文字、圆环、进程图标、按钮与交互焦点均保持可读
- **AND** 动画中不因背景重采样、材质重建或错误叠色出现闪烁与整体发灰不可读

### Requirement: 宿主迁移保留完整操作

模块内容及面板入口 SHALL 保持现有功能，包括数值复制、支持的排序操作、分页、原生控件、显示器控制、工具/设置/统计入口、钉住及关闭。隐藏明细 SHALL 不接收输入、不占键盘焦点并从辅助功能访问中隐藏；部分揭示时指针命中 SHALL 与当前可见内容一致。

#### Scenario: 可见内容操作
- **WHEN** 用户点击指标、切换电源分页、操作显示器滑杆或打开底部入口
- **THEN** 操作作用于当前所见组件，维持原有功能和渠道限制
- **AND** 手势不误触模块展开、窗口拖动或其他行的控件

#### Scenario: 用户调整顺序
- **WHEN** 用户通过已提供的排序入口调整模块或指标顺序
- **THEN** 新顺序作用于当前内容、运动和命中位置，并按既有规则持久化
- **AND** 隐藏项回归后保留位置，未完成的排序能力不得因本次迁移被声称已验收

#### Scenario: 收起带焦点的明细
- **WHEN** 用户收起内部有键盘焦点的分区
- **THEN** 焦点安全返回该分区的行头或既有等价位置
- **AND** 隐藏控件不继续响应 Tab、复制或辅助功能动作

#### Scenario: 运动中的可见命中
- **WHEN** 用户在展开/收起中点击正在移动的控件，或通过辅助功能切换分区
- **THEN** 命中位置对应当前呈现位置，辅助功能获得稳定的逻辑展开状态
- **AND** 不暴露不可见明细或逐帧播报运动进度

#### Scenario: 显示器控制页与档案页的输入隔离
- **WHEN** 显示器当前处于控制页且档案页保持透明用于自然尺寸登记
- **THEN** 滑杆和按钮的 AppKit 命中仅进入控制页，透明档案宿主不拦截输入
- **AND** 切换到档案页时命中仅进入档案页

#### Scenario: 内容换页和鼠标悬停不重播外壳
- **WHEN** 用户切换电源分页或移动鼠标到显示器控件
- **THEN** 内容保持顶部对齐，尺寸不变的更新不重复触发宿主尺寸失效或重播同一图层计划
- **AND** 换页高度沿统一轨迹变化，卡片材质不因内容重测而闪烁

#### Scenario: 自然明细与递归宿主的尺寸一致
- **WHEN** 原生卡片切换不同高度的分页，或显示器滑杆发布新数值
- **THEN** 明细摆放使用测量得到的完整自然高度，揭示范围由统一图层控制
- **AND** 子宿主继承扣除当前层左右内衬后的宽度，内容更新与布局测量不交替采用父宽度和子宽度

### Requirement: 固定底部操作区

面板内容超过可用高度时，监视器、工具和设置入口 SHALL 独立固定在可见面板底部，仅模块内容滚动；操作区 SHALL 保留现有动作、键盘访问、材质及完整标签，模块最后一项 SHALL 仍可完整滚动到达。

#### Scenario: 全部展开后的模块滚动
- **WHEN** 用户全部展开并滚动限高面板
- **THEN** 模块内容在标题与底部操作区之间滚动
- **AND** 底部按钮持续可见、位置不随滚动偏移变化且可操作

#### Scenario: 从限高恢复自然高度
- **WHEN** 收起模块使面板不再限高
- **THEN** 底部操作区沿统一轮廓轨迹跟随自然高度
- **AND** 模块与按钮保持原有间距，按钮不遮盖最后一项内容
