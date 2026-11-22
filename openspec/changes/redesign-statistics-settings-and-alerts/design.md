# Design

## Context

动机见 [proposal.md](proposal.md)。核心待解矛盾集中在三层：

1. **视觉与语义冲突**：原 `StatisticsSettingsView` 把实时进程观测 (`ProcessAlertCenter.activeAlerts`) 混放在以今日/近7日/近30日历史范围切换的概览卡中，且仅以最高瞬时档位为整条历史压力状态着色（如 245 小时内 3 分钟严重 + 182 小时 17 分钟警告被整行染成严重红，左侧再挂「✓」，并在分解文案里让人做减法心算）。
2. **警报失衡与噪声**：
   - CPU 固定 60% 阈值（单核基准）在 10–16 核 Apple Silicon 上相当于整机 3.7%–6% 负载即可触发高负载；
   - `SystemPressureSnapshot.hasElevatedPressure` 将热压力 `fair(1)` 视为系统承压并放行应用高负载通知；
   - `PressureAlertCenter` / `ProcessAlertCenter` 原本订阅过滤后的 `store.modules`，用户隐藏内存或 CPU 行即失去后台压力感知；
   - 缺乏跨事件通知冷却期，波动场景容易在短时间恢复重触后反复弹窗；用户无法按类别静音或豁免编译器/浏览器/游戏等常驻高负载应用；系统通知被拒权时应用内无反馈与跳转入口。
3. **后台精度与性能隐患**：
   - `StatisticsRecorder` 的快速批次与 `nettop` 独立网络批次共享单一 `lastProcessSampleAt` 游标，导致晚 200ms 到达的 `sampleNetwork` 只按 `0.2s` 积分并在多数时段跌破 5 MiB 落库下限，造成单应用网络流量被低估 200–300 倍；
   - `sampleTopMemoryProcesses` 默取前 5 条，在高负载内存统计中易漏报靠后大内存进程；
   - `week` / `month` 只查询 `hourRows`，整点第 5 分钟后因无新小时桶，近期压力频繁被误标为「观测中断」；
   - 未打开设置页时 `sealCompletedMinute()` 仍每分钟重算 30 天概览并执行 `StatsActiveDay`/`StatsUsageMeta` 读写；`StatsAppEvent` 无自动保留清理，退出时进程日累加器未同步落盘；`ReportDataAggregator` 未对历史事件 `appKey` 套用别名表。

## Goals / Non-Goals

**Goals:**
- 以「控制卡 → 条件式独立高占用横幅 → 统计概览主卡 → 存储管理入口」重构设置主页视觉层级。
- 以「极简分项开关（总开关 + 3 项分类）+ 忽略的应用白名单 + 15 分钟冷却 + 自适应门槛」平衡告警可信度与免打扰体验。
- 修复进程采样游标、周/月当前小时连续性、按可见性门控概览刷新及持久化生命周期。
- 严格遵循经典毛玻璃设计体系与既有 `SettingsGroup` / `SettingsRow` / `MonitorPalette` / `Localizable.xcstrings` 规范，双渠道（App Store 与直连版）无差异可用。

**Non-Goals:**
- 不改造独立原生统计报表窗口、HTML 导出报表及主面板展开交互。
- 不实现分应用自定义阈值滑块、导出告警规则模板或只读范围之外的 SMC 写入能力。

## Decisions

### 1. 统计页信息架构剥离、时钟完整度与环形占比状态双格 (`StatisticsOverviewModel.DimensionStatus` / `CoverageSummary`)
- **决策**：将实时活跃高负载应用从概览卡片内完全移除，独立为控制卡与概览卡之间的单行紧凑条 `ActiveHighLoadBanner`（仅在存在未被忽略的确认高负载应用时渲染）；历史概览卡片内部改为「范围切换器 + 右侧时钟完整度图标 `CoverageClockButton`」→「并排 `内存压力` | `热压力` 环形占比双格 `PressureStatusCell`」→「2×3 细线等分宫格」。
- **为什么状态栏选内存压力 + 热压力**：macOS 中 CPU/GPU 满载、功耗与网络/磁盘吞吐反映「系统干了多少活」，而「系统扛不扛得住」的跨机型（含无风扇 Air 与无电池桌面机）、双渠道通用官方状态信号只有「内存压力」与「热压力」，与 [StatisticsHealthScore.swift](file:///Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Statistics/StatisticsHealthScore.swift) 60/40 评估口径严格一致。
- **纯客观占比模型与环形图 + 悬浮明细交互**：
  - `StatisticsOverviewModel.coverageSummary(for:row:now:calendar:)` 计算已累计统计时长、当前窗口已流逝时长及完整度百分比，由顶栏右侧 `CoverageClockButton` 承载并在悬浮或点击时弹出完整度详情，释放顶栏文字空间。
  - `StatisticsOverviewModel.dimensionStatus(for:row:events:)` 折叠热状态 `fair(1)` 为正常档位 `0`，仅保留 `.noData` / `.insufficient` / `.normal` / `.hasPressure` 四种客观态，并按累计时长降序产出归一化的 `Slice` 列表（`abnormalSlices` + 正常切片总和为 `1.0`）；彻底删除主观阈值与「基本正常」「偶发警告」「压力较高」「短暂升高」等中间术语以及 `ⓘ` 按钮。
  - 格内使用 `40×40pt` `PressureDonutRing` 从 12 点钟方向顺时针绘制异常切片，并对极小非零异常施加 `0.045` 最小可见弧段与 `0.012` 切片间隙，确保 `<1%` 异常仍清晰可见；正文以占比为主（如「警告 74%」「严重 <1%」）并辅以内联 `[持续中]` / `[观测中断]` 徽章，隐藏直观耗时的分钟/小时文本以降低阅读负担。
  - 环形图与正文共享 `HoverPopoverController`（160ms 打开 / 180ms 关闭防抖 + `openedByClick` 状态），悬浮或点击后弹出 `PressureBreakdownPopover` 展示各原生档位精确时长、单小数占比与单行内联精简解释；下方 2×3 宫格内单值均值格统一改为 `平均 19%`（`avg 19%`）自然语序，首行 CPU / GPU 由 `StatisticsOverviewModel.workloadSummary(for:row:)` 与 `WorkloadMetricCell` 承载，复用现有 `valid_*_s` / `*_high_s` 直接展示「高负载 占比%」（无高负载时回退「峰值 %」）并在悬浮/点击 `WorkloadBreakdownPopover` 中展开比例条、精确时长、平均与峰值；双向网络（`↓`/`↑`）与磁盘读写（`读`/`写`）改为同字号平权两行。
- **替代方案**：单块长句结论、无坐标横向占比条，或带自造中间态文案的纯文本双格。实机多轮视觉评审表明纯文本与自造中间态难以建立直觉关联且精确时长加重阅读负担，故改为环形图直出占比、精确时长与定义全部收敛进悬浮/点击弹窗。

### 2. 极简分项开关 + 白名单 + 统一通知授权状态
- **决策**：新增 `AlertSettingsView` 承载三项互斥清晰的分项开关（`alertMemoryPressureEnabled`、`alertThermalPressureEnabled`、`alertHighLoadAppEnabled`）和 `alertIgnoredApps`（以 JSON 编码持久化在 `MonitorSettings`，按 `id`、`bundleIdentifier` 与大小写不敏感 `displayName` 匹配）；`AlertNotificationDelegate` 转为 `ObservableObject`，在初始化及 `NSApplication.didBecomeActiveNotification` / 打开页面时刷新系统通知授权状态，被拒时同时在设置主页入口行和子页顶部给出清晰状态与直达系统设置按钮。
- **权衡**：未提供每指标滑块配置，避免普通用户面对 4 类指标 × N 应用阈值的认知负担；白名单同时过滤活跃横幅与系统通知，但保留后台日统计和历史事件落库，保证关闭某应用提醒后在完整报表中仍能追查开销。

### 3. 自适应门槛与冷却机制
- **决策**：`StatisticsMetricDefinition.attentionThreshold(for: .cpu, logicalCoreCount:)` 采用 `max(100, Double(logicalCores) * 100 * 0.15)`（不可读时回退 100）；`SystemPressureSnapshot.hasElevatedPressure` 收紧为 `hasValidObservation && (memoryLevel >= 1 || thermalLevel >= 2)`；`PressureAlertCenter` 与 `ProcessAlertCenter` 共用 15 分钟跨事件冷却，同事件严重度升级不阻断，异步投递失败则回滚 `lastNotifiedAt` 与 `notifiedTiers`；两处告警中心均订阅 `MonitorStore.allModulesPublisher`。
- **替代方案**：仅调高瞬时持续门槛时间（例如从 120s 提至 300s）。单靠拉长持续窗口无法解决 16 核机器轻载常驻误触发和短暂波动后 3 分钟内二次弹窗问题，故采用「核数归一化门槛 + 15 分钟冷却」组合。

### 4. 分离游标、当前小时拼接与生命周期门控
- **决策**：
  - `StatisticsRecorder.recordProcesses` 将单一 `lastProcessSampleAt` 拆为 `lastFastProcessSampleAt` 与 `lastNetworkProcessSampleAt`，配合 `providedMetrics` 精准门控 `ProcessAlertCenter.settleUnobservedMetrics` 与网络速率积分；
  - 新增 `rangeMetricRows(for:database:now:)` 作为 `refreshOverview` 与 `rangeSeries` 唯一数据源，`week`/`month` 在已完成 `hourRows` 后追加当前整点起至今 `minuteRows` 的聚合行；
  - 新增 `setOverviewObservationActive(_:)` 仅在 `StatisticsSettingsView` 在屏（appear/disappear）期间开启分钟封口全量重算，避免与默认首页 `.general` 的设置窗口生命周期测试及日常无设置浏览产生不必要全表查询；
  - `StatisticsProcessStore` 增加内存 `lastRecordedUsageDay` 去重（并在删除接口里复位），补充 60 天 `StatsAppEvent` 自动淘汰与 `AppDelegate` 退出时仅针对已打开库的 `flushForTermination()`；`ProcessAlertCenter.resolveAppKey` 与 `ReportDataAggregator` 别名映射保证事件身份在重命名与历史回顾中一致。

## Risks / Trade-offs

- **CPU 门槛抬高导致部分既有单元测试硬编码 70% 失效** → 同步修改受影响测试使用与运行时同源的动态阈值，并在 `StatisticsMetricDefinitionTests` 固定覆盖 4/8/12/16 核与异常兜底边界。
- **测试期间 `ProcessAlertCenter` 使用非真实存活 PID** → `resolveAppKey(name:pid:)` 在 `AppIdentityResolver` 返回 `.unresolved`（包括 `pid <= 0` 或不存在 PID）时安全回退为显示名称 `name`，保持假 PID 测试兼容性。
- **`StatisticsSettingsView` 跳转子页后返回时需立刻同步概览** → 将 `setOverviewObservationActive(true)` 的开启时机绑定到 `StatisticsSettingsView.onAppear`，其内部每次从 `false -> true` 会触发一次 `loadOverview()`，确保从 `.alerts` / `.storage` 返回即刻显示最新数据。

## Verification Plan

- 编译验证：App Store (`HagimiMonitor`) 与 Direct (`HagimiMonitorDirect`) 双渠道 Debug 构建全绿，无新增警告或并发隔离错误。
- 全量测试：`HagimiMonitorDirect` 完整测试套件通过，新增/更新测试覆盖核数自适应阈值、双游标并发网络积分、周/月当前小时序列、`pressurePresentation` 客观严重度、15 分钟冷却与同事件升级、分项开关与白名单、本地化格式一致性。
- 人工验收：启动构建后的两个 `.app` 实机目测「数据统计」主页、三档时间范围、亮暗/色彩偏好主题及「异常警报」子页布局与交互。
