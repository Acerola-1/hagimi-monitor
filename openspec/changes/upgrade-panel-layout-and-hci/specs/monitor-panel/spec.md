# Spec Delta

## MODIFIED Requirements

### Requirement: Long Panel Content Handling
The panel SHALL handle long metric values, localized labels, display names, network identifiers, and storage volume names without overlapping adjacent UI. 指标网格布局 SHALL NOT 随每秒实时采样值的长度跳变而重排；布局在 A/B 对照期间分别支持「紧凑上下堆叠瓦片 + 规格行分离（方案 A）」或「基于当前面板宽度档位 × 语言 × 合理最坏值的静态容器断点（方案 B）」，不再强制全宽区间锁死在 300 pt 最窄半格登记表。

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
- **WHEN** 面板保持开启且指标数值在每秒采样期间发生位数增减或单位切换，或在当前宽度断点区间内微调面板宽度
- **THEN** 每个指标格的列跨度与所在行位置保持稳定，不发生动态重排或内容跳动
- **AND** 仅在用户切换语言或面板跨越预设容器宽度断点（方案 B）时才重新计算静态格位布局，方案 A 则在全支持区间保持堆叠与规格行分层稳定

### Requirement: 展开区指标行序
模块展开区指标网格在未自定义顺序时 SHALL 遵循既有分组顺序，用户调整顺序后 SHALL 按保存顺序排列；对于因开关隐藏或拖拽排序而产生的落单半格（奇数半格或整行指标前的孤立半格），方案 B SHALL 自动将其扩展铺满所在行以消除右侧空白缺口，方案 A SHALL 通过堆叠网格无空洞排布（与在途变更 `panel-long-press-reordering` 的旧留空规则在胜出方案裁决后统一收敛）。

#### Scenario: 整行与半行混合
- **WHEN** 某模块展开区同时含整行与半行指标，或用户把整行指标排到两个半行指标之间
- **THEN** 方案 B 下前一位落单半格自动撑满其所在行，整行指标从下一行起独立成行，模块尾部不再留出空白半格缺口
- **AND** 方案 A 下短数值瓦片与规格行按各自网格自然成行且不残留空白缺口

#### Scenario: 语义配对的整行指标
- **WHEN** 两个整行指标存在语义配对关系（如 Wi-Fi 信号与网关延迟）且未调整顺序
- **THEN** 二者在整行区内保持相邻与既定先后顺序
- **AND** 用户自定义顺序后尊重用户保存的排列顺序

### Requirement: 指标数值复制可发现且有结果
网络 IP 地址类指标（`ipv4`、`ipv6`、`public-ip`、`ip-address`）SHALL 将点击热区统一至整个指标格并支持按纯地址值写入剪贴板，提供复制用途提示、右键菜单与键盘/辅助技术可达命令，并在触发后于格内原地切换为带贴合连续圆角细描边的 `✓ 已复制` 状态（禁用系统默认直角焦点环）；其余非地址类指标格与整套展开网格 SHALL 保持静默不响应点击复制且不显示悬停变暗高亮，避免误触长按拖拽或产生过多视觉扰动。

#### Scenario: 连续复制不同数值
- **WHEN** 用户单击或右键点击 `ipv4`、`ipv6`、`public-ip` 或 `ip-address` 指标格
- **THEN** 剪贴板写入纯净地址值且匹配最后选定项
- **AND** 复制成功反馈在格内原地短暂展示后恢复，不挤动指标格尺寸且不触发行展开或拖拽排序

#### Scenario: 非地址指标不触发点击复制与悬停变暗
- **WHEN** 用户指针悬停或单击 CPU、内存、电池或其他非地址类网络指标格
- **THEN** 指标格保持静态底色不变暗且不触发剪贴板写入
- **AND** 长按达到拖拽阈值时正常进入指标排序流程

## ADDED Requirements

### Requirement: 主行标题对齐与状态可发现性
主面板模块行头 SHALL 在模块名称及冒号后按当前语言对齐左侧标题槽位（标题与主数值保持 `6pt` 紧凑间距），使各行主数值形成清晰纵向扫描线；行头右侧成对读数胶囊与蓝牙设备图标槽 SHALL 保持与内容比例协调的视觉对比；可展开模块 SHALL 提供悬停可展开箭头指示，不可展开模块行保持静态不弹出提示气泡；顶栏标题区 SHALL 在指针连续悬停满 2 秒后才呈现「双击展开或收起」提示，统计入口图标 SHALL 清晰表达统计语义。

#### Scenario: 保留冒号并对齐左槽扫描线
- **WHEN** 主面板呈现各监控模块及设置页预览卡
- **THEN** 主行标题保留冒号并按当前语言左槽宽度及紧凑间距对齐，各行主读数左起位置保持整齐对齐

#### Scenario: 紧贴型百分比符号排版一致
- **WHEN** 同一模块行头与展开明细渲染百分比读数
- **THEN** `%` 符号紧贴数字并与数值保持一致的视觉权重与字号节奏，不出现额外间隙裂开

#### Scenario: 不可展开行与顶栏延迟提示
- **WHEN** 用户指针悬停在可展开模块行头、单风扇等不可展开模块行头，或在顶栏 `SYSTEM · LIVE` 标题区连续悬停满 2 秒且未触发点击
- **THEN** 可展开行头呈现克制的可展开指示，不可展开行保持静态不弹出任何提示窗
- **AND** 顶栏标题区在悬停满 2 秒后显现简洁「双击展开或收起」浮层提示，点击或移出立即隐藏；统计入口图标清晰表达统计报表语义

### Requirement: CPU 逐核悬停原地反馈
悬停 CPU 逐核环形图中的单个核心时，面板 SHALL 对目标核心环施加轻量放大反馈并在圆环正上方（卡片水平安全边距内）以轻量磨砂胶囊浮层展示该核心的类别编号与占用率（如 `P2 · 45%`），下方 `P / E / S` 分组汇总栏 SHALL 保持常驻展示不被替换。

#### Scenario: 指针悬停单个核心环
- **WHEN** 用户将指针移入 CPU 逐核图中的某个核心环
- **THEN** 目标核心环呈现轻量放大并在其正上方显示该核心标识与占用率气泡
- **AND** 下方分组汇总栏始终稳定展示 P / E / S 各核心组的平均占用率，不被遮挡或替换

#### Scenario: 指针离开核心环区域
- **WHEN** 用户将指针移出逐核环形图区域
- **THEN** 核心环恢复原尺寸并隐藏上方数值气泡，下方分组汇总栏维持常驻显示

### Requirement: TOP 进程行交互与渠道边界
五类资源（CPU/GPU/内存/磁盘/网络）与电源 TOP 进程行 SHALL 支持悬停与原生右键快捷操作菜单；交互、右键菜单展开及退出确认期间 SHALL 按 PID 冻结列表顺序并在菜单打开瞬间按值快照目标 PID 与进程名，防止采样刷新造成目标错位；App Store 与 Direct 双渠道均 SHALL 支持前置激活 GUI 应用、复制进程名称/PID 及权限允许时在访达中显示；仅 Direct 分发渠道 SHALL 支持带二次确认的温和退出操作，且校验目标进程有效性并排除系统关键进程与本应用自身。

#### Scenario: 双渠道快捷定位与复制进程信息
- **WHEN** 用户在任意可用渠道下悬停或右键点击 TOP 进程行中的普通应用条目
- **THEN** 可执行前置激活该应用、复制进程名称或 PID，或在访达中显示可执行包
- **AND** 进程行中的快捷操作按钮点击不误触发行头展开或面板拖动

#### Scenario: Direct 渠道温和退出进程与安全校验
- **WHEN** 用户在 Direct 渠道下对非系统关键且非本应用的第三方进程触发退出操作
- **THEN** 界面先展示明确的二次确认交互再执行退出请求
- **AND** 执行前校验目标 PID 仍对应原进程身份，避免因采样刷新期间 PID 复用而误伤其他进程

#### Scenario: App Store 渠道权限边界
- **WHEN** 用户在 App Store 沙盒渠道下操作 TOP 进程行
- **THEN** 界面仅暴露前置激活、复制信息及允许的只读定位操作
- **AND** 不提供退出其他进程的入口

### Requirement: 展开指标网格 A/B 对照验收关卡
展开指标网格的改造 SHALL 先分别交付方案 A（堆叠瓦片与语义组合条）与方案 B（容器宽度响应式断点与孤项撑满）两份可运行版本进行同屏对照；仅在用户确认胜出方案后，才移除落选分支实现并收敛正式规格与设置页预览。

#### Scenario: A/B 并行构建与同屏对照
- **WHEN** 第二阶段开发完成并进入视觉裁决
- **THEN** 方案 A 与方案 B 均可分别编译运行并带清晰实例区分标记同屏展示
- **AND** 两者均保持设置页同源预览、长按拖拽排序及单宿主平滑展开动画
