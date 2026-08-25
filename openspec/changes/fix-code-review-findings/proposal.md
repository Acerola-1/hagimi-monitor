# 提案：落地全分支代码审查的验证发现

## Why

2026-08-25 对 dev 分支做了一次多维度全量审查（7 个维度并行扫描，62 条候选经双人对抗复核，9 条被证伪，53 条存活：1 critical / 9 high / 20 medium / 23 low）。结论：代码库底子好（采样并发纪律、SQLite 串行收口、报表注入防护均达标），但存在两处明确腐坏——**功能/健壮性缺陷簇**（伽马调光实测无效、子进程采样无看门狗、设置深链首次打开必丢、DDC 抑制窗口写入丢失、报表三处日期/口径错误）与**质量门禁失守**（9/141 单测失败、无任何 CI 在 push/PR 跑测试、沙盒 scheme 的测试构建因产物名冲突根本编不过——红测试跟着 v1.5.0 发了出去）。本变更规划全部验证发现的分批落地。

## What Changes

### 批次 A — P0 功能/健壮性修复（每项小且可独立验证）

- **A1** 修复伽马调光：`CGSetDisplayTransferByFormula` 参数槽位传错，每次调用以 kCGError 1007 失败，软件调光从不生效（已在 SDK 头文件 + 实机双重验证）
- **A2** 为 nettop / `/bin/ps` 子进程采样加挂起看门狗：复用同仓三处 system_profiler 探针的信号量超时 + `terminate()` 模式，消除子进程卡死永久堵死采样队列的风险
- **A3** 修复设置窗口深链：每次启动后首次"关于/统计"入口因广播早于观察者挂载而丢失目标标签页
- **A4** DDC 抑制窗口（睡眠/唤醒/重配置）内被跳过的写入在窗口结束后重放，兑现代码注释承诺
- **A5** MCDP29XX 父链搜索补 `kIORegistryIterateRecursively`，修复 HDMI 显示器 DDC 可能发往错误芯片地址
- **A6** 解除静音优先恢复 UserDefaults 持久化音量，而非固定 6.25% 兜底
- **A7** 报表自定义日期范围修复结束日多算一天（应用排行 + 电池健康两处）
- **A8** 报表每日表格改用本地午夜归一化步进，修复跨夏令时日行整段丢失
- **A9** 报表覆盖时长与分布图统一改用 `cover_s` 真实秒数口径
- **A10** 权限轮询定时器在用户拒绝后停止；快捷键录入器在设置窗口关闭（含录制中途关窗）时拆除按键监视器
- **A11** 网络 TOP 列表按负责进程归并，助手进程（WebContent/Helper）流量合并到宿主应用，与其余四类列表口径一致

### 批次 B — P1 质量门禁（必须先于批次 C，否则后续修复无验证手段）

- **B1** 修绿 9 个失败单测（菜单栏格式化去补零、默认指标选择、统计睡眠间隙口径——均为实现已改测试未跟）
- **B2** 修复沙盒（App Store）scheme 测试构建：双 `HagimiMonitor.app` 产物名冲突 + 单测 TestTargetID 指向错误宿主
- **B3** 新增 CI：push/PR 触发，构建并测试两个 scheme
- **B4** 统计汇总增量化：`maintain()` 的 rollUp 从"每分钟全窗口重扫"改为增量封口，开销不再随数据年龄线性增长（与"常年零 IO"设计宣称对齐）
- **B5** 遥测增加用户退出开关（小项）

### 批次 C — P2 结构性偿还（每项独立提交）

- **C1** `MonitorPanelView`（3712 行）首批拆分：抽出 Canvas 电源流渲染器、三个逐字重复的 TOP 进程列表视图（合并为一个参数化视图）、死代码（PowerFlowDiagram 死 Canvas、autotest 脚手架出生产路径）
- **C2** 展开状态机收敛：统一两个面板控制器逐字重复且已分叉的竞态防护代码为共享实现；清理仍描述已删除 60Hz-Timer 设计的过期注释
- **C3** 指标 name 裸字符串契约改共享枚举/常量；`MonitorSettings` 迁移逻辑守护空集合（用户全关的指标不再被静默复活）
- **C4** `Top*Process` 五文件（~989 行）的分组/过滤/富化管线合并为共享实现
- **C5** 死代码清理：`DisplayDDCBridge.read()`（零调用）、`ContentView`、`SettingsTab.modules`、四个零引用动画常量、桶级删除路径、散落 UserDefaults 键归拢

### 卫生项（任意时间，独立提交）

- **H1** 删除工作树 ~9.6 GB 本地垃圾：`tmp/`（6.6 GB，10 个 DerivedData 克隆）、`build/`（3.0 GB）
- **H2** 移除 `docs/synth-beam-main/`（70 文件无关 React 脚手架）
- **H3** `.gitignore` 增加 `.DS_Store`（当前仅靠用户全局 gitignore）
- **H4** `release.sh` tag 守卫改为查询远端、收紧 workspace 检查正则
- **H5** gh-pages 删除主分支已不存在的孤儿 `privacy.html`

### 明确不做（另立变更跟进）

- `MonitorStore` / `FluidPanelController` 全面拆分（影响面大，需独立设计）
- WiFiProbe 拆出独立采样队列（需采样管线整体评估）
- `MetricGlassRow` 手工 Equatable 重构（随 C1 拆分顺带评估，不单独立项）

## Capabilities

### New Capabilities

- `subprocess-sampling-watchdog`: 子进程采样（nettop/ps）的挂起防护——超时即终止并跳过该次采样，采样队列永不因单个子进程卡死而堵塞
- `display-control-correctness`: Direct 构建显示器控制的正确性——伽马调光生效、抑制窗口跳过的写入被重放、HDMI 芯片地址探测递归、解除静音恢复持久化音量
- `report-data-accuracy`: 网页报表数据口径——自定义范围排他边界、本地日历日期遍历、覆盖时长按真实秒数
- `statistics-background-maintenance`: 统计后台维护——分钟封口后的汇总为增量式，单次维护开销有界，不随数据年龄增长

### Modified Capabilities

- `settings-window`: 深链打开直达目标标签页（含每次启动首次打开）；快捷键录入器随窗口关闭拆除；权限轮询在拒绝后停止；遥测可退出
- `panel-animation-consistency`: 多行同时展开时滚动揭示目标确定（非任意）；沙盒版显示器信息分区参与面板隐藏/默认展开重置，与 Direct 构建行为一致
- `monitor-panel`: 网络 TOP 列表按负责进程归并助手进程流量；用户关闭的模块指标在重启后保持关闭

## Impact

- **代码**：`HagimiMonitorDirectOnly/`（GammaDimmingController、DisplayDDCBridge、DisplayControlsSection、MediaKeyController）、`HagimiMonitor/`（TopNetworkProcess、TopCPUProcess、SettingsWindowPresenter、MonitorSettings、InputMonitoringPermissionService、Views/Settings/GeneralSettingsView、Statistics/StatisticsDatabase、MonitorPanelView）、`HagimiMonitor/Resources/ReportTemplate.html`、`HagimiMonitorTests/`、`hagimi-monitor.xcodeproj/project.pbxproj`、`.github/workflows/`、`scripts/release.sh`
- **行为变化**（均为用户可感知修复）：伽马调光从失效变为生效；解除静音恢复到持久化音量；报表在自定义范围/夏令时/覆盖时长三处数字变准确；网络 TOP 列表合并助手进程；指标关闭选择跨重启保留；设置深链始终直达
- **无破坏性变更**：不涉及数据迁移、不改变设置键格式、App Store 与 Direct 双目标结构不变
- **风险**：A4（DDC 重放）与 B4（汇总增量化）触碰数据路径，需在批次 B 的 CI 就位后落地并配测试
